// 会议邮件通知服务：创建通知 + 会前 8 小时提醒
package service

import (
	"context"
	"log"
	"strings"
	"time"

	"meeting-platform/config"
	"meeting-platform/internal/model"
	"meeting-platform/internal/repository"
	"meeting-platform/pkg/mailer"
)

// NotificationService 会议邮件通知服务
type NotificationService struct {
	meetingRepo *repository.MeetingRepository
	mail        *mailer.Mailer
	cfg         *config.Config
}

// NewNotificationService 创建通知服务
func NewNotificationService(
	meetingRepo *repository.MeetingRepository,
	m *mailer.Mailer,
	cfg *config.Config,
) *NotificationService {
	return &NotificationService{meetingRepo: meetingRepo, mail: m, cfg: cfg}
}

// NotifyMeetingCreated 异步入口：会议创建后发送邀请邮件
func (n *NotificationService) NotifyMeetingCreated(meetingID string) {
	sent, err := n.SendInvites(meetingID)
	if err != nil {
		log.Printf("[MAIL] meeting %s invite failed: %v\n", meetingID, err)
		return
	}
	log.Printf("[MAIL] meeting %s invite sent to %d participant(s)\n", meetingID, sent)
}

// SendInvites 给会议全体参会者发送邀请邮件（跳过组织者本人与无邮箱用户）
// 通过 notified_at 去重，重复调用不会重复发送
func (n *NotificationService) SendInvites(meetingID string) (int, error) {
	meeting, err := n.meetingRepo.FindByID(meetingID)
	if err != nil {
		return 0, err
	}
	if meeting.NotifiedAt != nil {
		return 0, nil
	}

	sent, failed := n.broadcast(meeting, false)
	// 无论部分失败与否都标记已发送，避免重复轰炸
	_ = n.meetingRepo.MarkNotified(meetingID, time.Now())
	if failed > 0 {
		log.Printf("[MAIL] meeting %s invite: sent=%d failed=%d\n", meetingID, sent, failed)
	}
	return sent, nil
}

// SendReminder 发送会前 8 小时提醒
// 若创建时间距会议开始不足 8 小时，则只发创建通知，跳过提醒（仅标记已处理）
func (n *NotificationService) SendReminder(meetingID string) (int, error) {
	meeting, err := n.meetingRepo.FindByID(meetingID)
	if err != nil {
		return 0, err
	}
	if meeting.ReminderSentAt != nil || meeting.Status != model.StatusScheduled {
		return 0, nil
	}

	// 创建时间距开始不足 8 小时 → 只发一次
	if meeting.StartTime.Sub(meeting.CreatedAt) < 8*time.Hour {
		_ = n.meetingRepo.MarkReminderSent(meetingID, time.Now())
		return 0, nil
	}

	sent, failed := n.broadcast(meeting, true)
	_ = n.meetingRepo.MarkReminderSent(meetingID, time.Now())
	if failed > 0 {
		log.Printf("[MAIL] meeting %s reminder: sent=%d failed=%d\n", meetingID, sent, failed)
	}
	return sent, nil
}

// StartReminderLoop 启动会前提醒调度循环（每分钟扫描一次，直到 ctx 取消）
func (n *NotificationService) StartReminderLoop(ctx context.Context) {
	log.Println("[MAIL] reminder scheduler started (interval=1m, lead=8h)")
	n.scanReminders()

	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			log.Println("[MAIL] reminder scheduler stopped")
			return
		case <-ticker.C:
			n.scanReminders()
		}
	}
}

// scanReminders 扫描所有到期待提醒的会议并逐条处理
func (n *NotificationService) scanReminders() {
	due, err := n.meetingRepo.ListDueReminders(time.Now())
	if err != nil {
		log.Printf("[MAIL] scan reminders failed: %v\n", err)
		return
	}
	for _, m := range due {
		if _, err := n.SendReminder(m.ID.String()); err != nil {
			log.Printf("[MAIL] meeting %s reminder failed: %v\n", m.ID, err)
		}
	}
}

// broadcast 向会议参会者群发邮件，返回成功/失败数量
func (n *NotificationService) broadcast(meeting *model.Meeting, reminder bool) (sent, failed int) {
	organizerName := "会议组织者"
	organizerEmail := ""
	if meeting.Organizer != nil {
		organizerName = meeting.Organizer.Name
		organizerEmail = meeting.Organizer.Email
	}

	for _, p := range meeting.Participants {
		// 跳过组织者本人、无关联用户、无邮箱用户
		if p.User == nil || p.User.Email == "" || p.UserID == meeting.OrganizerID {
			continue
		}
		data := n.buildEmailData(meeting, p.User.Name, organizerName, organizerEmail)

		var subject, textBody, htmlBody string
		var err error
		if reminder {
			subject, textBody, htmlBody, err = renderReminderEmail(data)
		} else {
			subject, textBody, htmlBody, err = renderInviteEmail(data)
		}
		if err != nil {
			failed++
			log.Printf("[MAIL] render template failed (%s): %v\n", p.User.Email, err)
			continue
		}

		err = n.mail.Send(mailer.Message{
			FromName: organizerName,       // 发件人显示名 = 创建会议人员姓名
			FromAddr: n.cfg.SMTP.User,     // 实际投递账号（平台 SMTP）
			ReplyTo:  organizerEmail,      // 回复地址 = 组织者邮箱
			To:       []string{p.User.Email},
			Subject:  subject,
			TextBody: textBody,
			HTMLBody: htmlBody,
		})
		if err != nil {
			failed++
			log.Printf("[MAIL] send to %s failed: %v\n", p.User.Email, err)
			continue
		}
		sent++
	}
	return sent, failed
}

// buildEmailData 组装邮件模板数据
func (n *NotificationService) buildEmailData(
	meeting *model.Meeting,
	recipientName, organizerName, organizerEmail string,
) emailData {
	description := meeting.Description
	if description == "" {
		description = "暂无描述"
	}
	return emailData{
		RecipientName:      recipientName,
		OrganizerName:      organizerName,
		OrganizerEmail:     organizerEmail,
		MeetingTitle:       meeting.Title,
		MeetingTime:        formatMeetingTime(meeting.StartTime, meeting.EndTime),
		MeetingDescription: description,
		MeetingLink:        strings.TrimRight(n.cfg.App.BaseURL, "/") + "/meetings/" + meeting.ID.String(),
	}
}

// formatMeetingTime 格式化为北京时间：2026年01月15日 14:00 - 15:00
func formatMeetingTime(start time.Time, end *time.Time) string {
	loc := beijingLocation()
	s := start.In(loc).Format("2006年01月02日 15:04")
	if end != nil {
		s += " - " + end.In(loc).Format("15:04")
	}
	return s
}

// beijingLocation 返回东八区时区（tzdata 缺失时退化为固定时区）
func beijingLocation() *time.Location {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return time.FixedZone("CST", 8*3600)
	}
	return loc
}
