// Package mailer 提供基于 SMTP 的邮件发送能力（支持 QQ 邮箱 465 隐式 TLS / 587 STARTTLS）
package mailer

import (
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"log"
	"mime"
	"net"
	"net/smtp"
	"strconv"
	"strings"

	"meeting-platform/config"
)

// Message 一封待发送的邮件
type Message struct {
	FromName string   // 发件人显示名（会议组织者姓名）
	FromAddr string   // 发件地址（SMTP 登录账号）
	ReplyTo  string   // 回复地址（会议组织者邮箱）
	To       []string // 收件人列表
	Subject  string   // 邮件主题
	TextBody string   // 纯文本正文
	HTMLBody string   // HTML 正文
}

// Mailer SMTP 邮件发送器
type Mailer struct {
	cfg config.SMTPConfig
}

// New 创建邮件发送器
func New(cfg config.SMTPConfig) *Mailer {
	return &Mailer{cfg: cfg}
}

// Enabled SMTP 是否已配置；未配置时退化为日志输出（开发模式）
func (m *Mailer) Enabled() bool {
	return m.cfg.Enabled()
}

// Send 发送一封邮件；未配置 SMTP 时仅打印日志，便于本地联调
func (m *Mailer) Send(msg Message) error {
	if len(msg.To) == 0 {
		return nil
	}
	if !m.Enabled() {
		log.Printf("[MAIL-DEV] to=%s subject=%q\n%s\n", strings.Join(msg.To, ","), msg.Subject, msg.TextBody)
		return nil
	}

	fromAddr := msg.FromAddr
	if fromAddr == "" {
		fromAddr = m.cfg.User
	}
	// 发件人显示名：优先组织者姓名，否则用配置的默认发件名
	displayName := msg.FromName
	if displayName == "" {
		displayName = m.cfg.FromName
	}

	raw := buildMIME(displayName, fromAddr, msg.ReplyTo, msg.To, msg.Subject, msg.TextBody, msg.HTMLBody)
	return m.deliver(fromAddr, msg.To, raw)
}

// deliver 建立 SMTP 连接并投递邮件
// 端口 465 使用隐式 TLS（QQ 邮箱），其他端口尝试 STARTTLS
func (m *Mailer) deliver(from string, to []string, raw []byte) error {
	addr := net.JoinHostPort(m.cfg.Host, strconv.Itoa(m.cfg.Port))
	tlsCfg := &tls.Config{ServerName: m.cfg.Host}

	var client *smtp.Client
	if m.cfg.Port == 465 {
		conn, err := tls.Dial("tcp", addr, tlsCfg)
		if err != nil {
			return fmt.Errorf("smtp tls dial: %w", err)
		}
		client, err = smtp.NewClient(conn, m.cfg.Host)
		if err != nil {
			return fmt.Errorf("smtp new client: %w", err)
		}
	} else {
		c, err := smtp.Dial(addr)
		if err != nil {
			return fmt.Errorf("smtp dial: %w", err)
		}
		if ok, _ := c.Extension("STARTTLS"); ok {
			if err := c.StartTLS(tlsCfg); err != nil {
				return fmt.Errorf("smtp starttls: %w", err)
			}
		}
		client = c
	}
	defer client.Close()

	// 认证
	auth := smtp.PlainAuth("", m.cfg.User, m.cfg.Password, m.cfg.Host)
	if ok, _ := client.Extension("AUTH"); ok {
		if err := client.Auth(auth); err != nil {
			return fmt.Errorf("smtp auth: %w", err)
		}
	}

	if err := client.Mail(from); err != nil {
		return fmt.Errorf("smtp mail: %w", err)
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return fmt.Errorf("smtp rcpt %s: %w", rcpt, err)
		}
	}

	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("smtp data: %w", err)
	}
	if _, err := w.Write(raw); err != nil {
		return fmt.Errorf("smtp write: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("smtp close data: %w", err)
	}
	return client.Quit()
}

// buildMIME 构造 multipart/alternative 邮件报文（纯文本 + HTML 双版本）
func buildMIME(fromName, fromAddr, replyTo string, to []string, subject, textBody, htmlBody string) []byte {
	boundary := "==meeting-platform-alt-boundary=="
	var b strings.Builder

	b.WriteString("From: " + mime.QEncoding.Encode("UTF-8", fromName) + " <" + fromAddr + ">\r\n")
	b.WriteString("To: " + strings.Join(to, ", ") + "\r\n")
	if replyTo != "" {
		b.WriteString("Reply-To: " + replyTo + "\r\n")
	}
	b.WriteString("Subject: " + mime.QEncoding.Encode("UTF-8", subject) + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: multipart/alternative; boundary=\"" + boundary + "\"\r\n\r\n")

	// 纯文本部分
	b.WriteString("--" + boundary + "\r\n")
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	b.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
	b.WriteString(wrapBase64(textBody))
	b.WriteString("\r\n")

	// HTML 部分
	b.WriteString("--" + boundary + "\r\n")
	b.WriteString("Content-Type: text/html; charset=UTF-8\r\n")
	b.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
	b.WriteString(wrapBase64(htmlBody))
	b.WriteString("\r\n")

	b.WriteString("--" + boundary + "--\r\n")
	return []byte(b.String())
}

// wrapBase64 对正文做 base64 编码并按 76 字符换行（符合 RFC 2045）
func wrapBase64(s string) string {
	encoded := base64.StdEncoding.EncodeToString([]byte(s))
	var b strings.Builder
	for i := 0; i < len(encoded); i += 76 {
		end := i + 76
		if end > len(encoded) {
			end = len(encoded)
		}
		b.WriteString(encoded[i:end])
		b.WriteString("\r\n")
	}
	return b.String()
}
