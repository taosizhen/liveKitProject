// 邮件模板：会议邀请（创建时发送）与会前 8 小时提醒
package service

import (
	"bytes"
	"fmt"
	htmltmpl "html/template"
	texttmpl "text/template"
)

// emailData 邮件模板渲染数据
type emailData struct {
	RecipientName      string // 参会者姓名
	OrganizerName      string // 组织者姓名
	OrganizerEmail     string // 组织者邮箱（Reply-To）
	MeetingTitle       string // 会议名称
	MeetingTime        string // 会议时间（已格式化为北京时间）
	MeetingDescription string // 会议描述
	MeetingLink        string // 会议详情/入会链接
}

// 纯文本模板
var (
	inviteTextTmpl = texttmpl.Must(texttmpl.New("inviteText").Parse(`您好，{{.RecipientName}}：

{{.OrganizerName}} 邀请您参加以下会议，请准时出席。

会议名称：{{.MeetingTitle}}
会议时间：{{.MeetingTime}}
组织者：{{.OrganizerName}}（{{.OrganizerEmail}}）
会议描述：
{{.MeetingDescription}}

查看会议详情并加入会议：{{.MeetingLink}}

温馨提示：建议提前 5 分钟进入会议，并检查摄像头与麦克风。

—— 本邮件由在线会议协作平台自动发送，请勿直接回复。`))

	reminderTextTmpl = texttmpl.Must(texttmpl.New("reminderText").Parse(`您好，{{.RecipientName}}：

您参加的会议将在约 8 小时后开始，请提前安排时间。

会议名称：{{.MeetingTitle}}
会议时间：{{.MeetingTime}}
组织者：{{.OrganizerName}}
会议描述：
{{.MeetingDescription}}

查看会议详情并加入会议：{{.MeetingLink}}

—— 本邮件由在线会议协作平台自动发送，请勿直接回复。`))
)

// 通用 HTML 邮件骨架（内联样式，兼容主流邮件客户端）
const htmlEmailLayout = `<!DOCTYPE html>
<html><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:24px;background:#f3f4f6;font-family:-apple-system,'Segoe UI','Microsoft YaHei',sans-serif;">
  <div style="max-width:600px;margin:0 auto;">
    <div style="background:#2563eb;color:#ffffff;padding:20px 24px;border-radius:8px 8px 0 0;">
      <div style="font-size:14px;opacity:.85;">{{.Tag}}</div>
      <div style="font-size:20px;font-weight:600;margin-top:6px;">{{.Data.MeetingTitle}}</div>
    </div>
    <div style="padding:24px;background:#ffffff;border:1px solid #e5e7eb;border-top:none;border-radius:0 0 8px 8px;">
      <p style="margin:0 0 16px;color:#374151;">您好，{{.Data.RecipientName}}：</p>
      <p style="margin:0 0 20px;color:#374151;">{{.Lead}}</p>
      <table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151;">
        <tr>
          <td style="padding:8px 0;color:#6b7280;width:88px;">会议名称</td>
          <td style="padding:8px 0;">{{.Data.MeetingTitle}}</td>
        </tr>
        <tr>
          <td style="padding:8px 0;color:#6b7280;">会议时间</td>
          <td style="padding:8px 0;">{{.Data.MeetingTime}}</td>
        </tr>
        <tr>
          <td style="padding:8px 0;color:#6b7280;">组织者</td>
          <td style="padding:8px 0;">{{.Data.OrganizerName}}（{{.Data.OrganizerEmail}}）</td>
        </tr>
        <tr>
          <td style="padding:8px 0;color:#6b7280;vertical-align:top;">会议描述</td>
          <td style="padding:8px 0;">{{.Data.MeetingDescription}}</td>
        </tr>
      </table>
      <div style="text-align:center;margin:28px 0 8px;">
        <a href="{{.Data.MeetingLink}}" style="display:inline-block;background:#2563eb;color:#ffffff;text-decoration:none;padding:12px 28px;border-radius:6px;font-size:15px;font-weight:500;">{{.ButtonText}}</a>
      </div>
      {{if .Tip}}<p style="font-size:13px;color:#9ca3af;margin:16px 0 0;">{{.Tip}}</p>{{end}}
    </div>
    <p style="font-size:12px;color:#9ca3af;text-align:center;margin-top:12px;">本邮件由在线会议协作平台自动发送，请勿直接回复。</p>
  </div>
</body></html>`

// htmlPageData HTML 邮件的页面级数据
type htmlPageData struct {
	Tag        string
	Lead       string
	ButtonText string
	Tip        string
	Data       emailData
}

var inviteHTMLTmpl = htmltmpl.Must(htmltmpl.New("inviteHtml").Parse(htmlEmailLayout))
var reminderHTMLTmpl = htmltmpl.Must(htmltmpl.New("reminderHtml").Parse(htmlEmailLayout))

// renderInviteEmail 渲染会议邀请邮件，返回主题、纯文本、HTML
func renderInviteEmail(d emailData) (subject, textBody, htmlBody string, err error) {
	subject = fmt.Sprintf("会议邀请｜%s · %s", d.MeetingTitle, d.MeetingTime)
	textBody, err = renderText(inviteTextTmpl, d)
	if err != nil {
		return "", "", "", err
	}
	htmlBody, err = renderHTML(inviteHTMLTmpl, htmlPageData{
		Tag:        "会议邀请",
		Lead:       d.OrganizerName + " 邀请您参加以下会议，请准时出席。",
		ButtonText: "查看会议详情 / 进入会议",
		Tip:        "温馨提示：建议提前 5 分钟进入会议，并检查摄像头与麦克风。",
		Data:       d,
	})
	return subject, textBody, htmlBody, err
}

// renderReminderEmail 渲染会前 8 小时提醒邮件，返回主题、纯文本、HTML
func renderReminderEmail(d emailData) (subject, textBody, htmlBody string, err error) {
	subject = fmt.Sprintf("会议提醒｜%s 将于 %s 开始", d.MeetingTitle, d.MeetingTime)
	textBody, err = renderText(reminderTextTmpl, d)
	if err != nil {
		return "", "", "", err
	}
	htmlBody, err = renderHTML(reminderHTMLTmpl, htmlPageData{
		Tag:        "会议提醒",
		Lead:       "您参加的会议将在约 8 小时后开始，请提前安排时间。",
		ButtonText: "进入会议",
		Data:       d,
	})
	return subject, textBody, htmlBody, err
}

// renderText 渲染纯文本模板
func renderText(t *texttmpl.Template, d emailData) (string, error) {
	var buf bytes.Buffer
	if err := t.Execute(&buf, d); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// renderHTML 渲染 HTML 模板
func renderHTML(t *htmltmpl.Template, d htmlPageData) (string, error) {
	var buf bytes.Buffer
	if err := t.Execute(&buf, d); err != nil {
		return "", err
	}
	return buf.String(), nil
}
