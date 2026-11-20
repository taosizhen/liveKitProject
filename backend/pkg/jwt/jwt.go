// Package jwtutil 提供 JWT Token 签发与解析
package jwtutil

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims 自定义 JWT 声明（嵌入 RegisteredClaims + 业务字段）
type Claims struct {
	UserID string `json:"uid"`
	Email  string `json:"email"`
	Name   string `json:"name"`
	Role   string `json:"role"`
	Type   string `json:"type"` // access / refresh
	jwt.RegisteredClaims
}

// Signer JWT 签发器
type Signer struct {
	secret           []byte
	expireHours      int
	refreshExpireDay int
}

// NewSigner 创建 JWT 签发器实例
func NewSigner(secret string, expireHours, refreshExpireDay int) *Signer {
	return &Signer{
		secret:           []byte(secret),
		expireHours:      expireHours,
		refreshExpireDay: refreshExpireDay,
	}
}

// IssueAccessToken 签发访问 Token（短期）
func (s *Signer) IssueAccessToken(userID, email, name, role string) (string, error) {
	claims := Claims{
		UserID: userID,
		Email:  email,
		Name:   name,
		Role:   role,
		Type:   "access",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(s.expireHours) * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "meeting-platform",
			Subject:   userID,
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.secret)
}

// IssueRefreshToken 签发刷新 Token（长期）
func (s *Signer) IssueRefreshToken(userID string) (string, error) {
	claims := jwt.RegisteredClaims{
		Subject:   userID,
		ExpiresAt: jwt.NewNumericDate(time.Now().AddDate(0, 0, s.refreshExpireDay)),
		IssuedAt:  jwt.NewNumericDate(time.Now()),
		Issuer:    "meeting-platform",
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.secret)
}

// Parse 解析并校验 Token，返回 Claims
func (s *Signer) Parse(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return s.secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

// ParseRefresh 解析 Refresh Token（仅校验有效期）
func (s *Signer) ParseRefresh(tokenStr string) (string, error) {
	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return s.secret, nil
	})
	if err != nil {
		return "", err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("invalid refresh token")
	}
	sub, ok := claims["sub"].(string)
	if !ok {
		return "", errors.New("missing sub claim")
	}
	return sub, nil
}
