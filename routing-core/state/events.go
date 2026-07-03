package state

import (
	"time"

	"github.com/kaixuan/llm-gateway-go/errorsx"
)

type EventType int

const (
	EventSuccess EventType = iota
	EventFailureAuth
	EventFailureQuota
	EventFailureNetwork
	EventFailureRateLimit
	EventFailureTimeout
	EventFailureConcurrent
	EventFailureUpstreamDown
	EventFailureStreamTimeout
	EventManualDisable
	EventManualEnable
	EventManualSuspend
	EventProbeSuccess
	EventProbeFailure
)

type StateEvent struct {
	Type         EventType
	CredentialID int
	Model        string
	RequestID    string
	ErrorKind    errorsx.ErrorKind
	ErrorDetail  string
	RetryAfter   time.Duration
	Operator     string
	Timestamp    time.Time
}

type EventResult struct {
	Event    StateEvent
	Applied  bool
	OldState string
	NewState string
	Error    error
}

func NewSuccessEvent(credID int, model, requestID string) StateEvent {
	return StateEvent{
		Type:         EventSuccess,
		CredentialID: credID,
		Model:        model,
		RequestID:    requestID,
		Timestamp:    time.Now(),
	}
}

func NewFailureEvent(credID int, model, requestID string, kind errorsx.ErrorKind, detail string) StateEvent {
	return StateEvent{
		Type:         mapErrorKindToEventType(kind),
		CredentialID: credID,
		Model:        model,
		RequestID:    requestID,
		ErrorKind:    kind,
		ErrorDetail:  detail,
		Timestamp:    time.Now(),
	}
}

func NewFailureEventWithRetryAfter(credID int, model, requestID string, kind errorsx.ErrorKind, detail string, retryAfter time.Duration) StateEvent {
	evt := NewFailureEvent(credID, model, requestID, kind, detail)
	evt.RetryAfter = retryAfter
	return evt
}

func NewManualDisableEvent(credID int, operator string) StateEvent {
	return StateEvent{
		Type:         EventManualDisable,
		CredentialID: credID,
		Operator:     operator,
		Timestamp:    time.Now(),
	}
}

func NewManualEnableEvent(credID int, operator string) StateEvent {
	return StateEvent{
		Type:         EventManualEnable,
		CredentialID: credID,
		Operator:     operator,
		Timestamp:    time.Now(),
	}
}

func NewManualSuspendEvent(credID int, operator string) StateEvent {
	return StateEvent{
		Type:         EventManualSuspend,
		CredentialID: credID,
		Operator:     operator,
		Timestamp:    time.Now(),
	}
}

func mapErrorKindToEventType(kind errorsx.ErrorKind) EventType {
	switch kind {
	case errorsx.KindAuth, errorsx.KindAuthRevoked:
		return EventFailureAuth
	case errorsx.KindQuota, errorsx.KindQuotaBalance, errorsx.KindQuotaPeriodic, errorsx.KindQuotaPermanent:
		return EventFailureQuota
	case errorsx.KindNetwork:
		return EventFailureNetwork
	case errorsx.KindRateLimit:
		return EventFailureRateLimit
	case errorsx.KindTimeout:
		return EventFailureTimeout
	case errorsx.KindConcurrent:
		return EventFailureConcurrent
	case errorsx.KindUpstreamDown:
		return EventFailureUpstreamDown
	case errorsx.KindStreamTimeout:
		return EventFailureStreamTimeout
	default:
		return EventFailureNetwork
	}
}
