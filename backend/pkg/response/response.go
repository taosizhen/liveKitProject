// Package response 提供统一的 HTTP 响应格式
package response

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// Response 统一响应结构
type Response struct {
	Code    int         `json:"code"`              // 业务状态码（0 = 成功）
	Message string      `json:"message"`           // 提示信息
	Data    interface{} `json:"data,omitempty"`    // 业务数据
	Error   *ErrorDetail `json:"error,omitempty"`  // 错误详情
}

// ErrorDetail 错误详情
type ErrorDetail struct {
	Type   string `json:"type"`
	Detail string `json:"detail,omitempty"`
}

// PageData 分页数据包装
type PageData struct {
	Items    interface{} `json:"items"`
	Total    int64       `json:"total"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
	Pages    int         `json:"pages"`
}

// OK 返回成功响应
func OK(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{
		Code:    0,
		Message: "ok",
		Data:    data,
	})
}

// Created 返回创建成功响应
func Created(c *gin.Context, data interface{}) {
	c.JSON(http.StatusCreated, Response{
		Code:    0,
		Message: "created",
		Data:    data,
	})
}

// Paginated 返回分页成功响应
func Paginated(c *gin.Context, items interface{}, total int64, page, pageSize int) {
	pages := int(total) / pageSize
	if int(total)%pageSize > 0 {
		pages++
	}
	if pages == 0 {
		pages = 1
	}
	OK(c, PageData{
		Items:    items,
		Total:    total,
		Page:     page,
		PageSize: pageSize,
		Pages:    pages,
	})
}

// Fail 返回业务失败响应（HTTP 200，但 code != 0）
func Fail(c *gin.Context, code int, message string) {
	c.JSON(http.StatusOK, Response{
		Code:    code,
		Message: message,
	})
	c.Abort()
}

// BadRequest 参数错误（HTTP 400）
func BadRequest(c *gin.Context, message string) {
	c.JSON(http.StatusBadRequest, Response{
		Code:    400,
		Message: message,
	})
	c.Abort()
}

// Unauthorized 未授权（HTTP 401）
func Unauthorized(c *gin.Context, message string) {
	c.JSON(http.StatusUnauthorized, Response{
		Code:    401,
		Message: message,
	})
	c.Abort()
}

// Forbidden 无权限（HTTP 403）
func Forbidden(c *gin.Context, message string) {
	c.JSON(http.StatusForbidden, Response{
		Code:    403,
		Message: message,
	})
	c.Abort()
}

// NotFound 资源不存在（HTTP 404）
func NotFound(c *gin.Context, resource string) {
	c.JSON(http.StatusNotFound, Response{
		Code:    404,
		Message: resource + " not found",
	})
	c.Abort()
}

// ServerError 服务端错误（HTTP 500）
func ServerError(c *gin.Context, err error) {
	c.JSON(http.StatusInternalServerError, Response{
		Code:    500,
		Message: "internal server error",
		Error: &ErrorDetail{
			Type:   "internal_error",
			Detail: err.Error(),
		},
	})
	c.Abort()
}
