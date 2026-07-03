package state

import (
	"context"
	"fmt"
	"sync"
)

type Entity interface {
	GetState() string
	SetState(state string)
}

type FSM struct {
	mu          sync.RWMutex
	name        string
	states      map[string]*State
	transitions map[string][]*Transition
}

type State struct {
	Name       string
	OnEnter    func(ctx context.Context, entity Entity) error
	OnExit     func(ctx context.Context, entity Entity) error
	IsTerminal bool
}

type Transition struct {
	From   string
	To     string
	Event  EventType
	Guard  func(ctx context.Context, entity Entity) (bool, error)
	Action func(ctx context.Context, entity Entity) error
}

func NewFSM(name string) *FSM {
	return &FSM{
		name:        name,
		states:      make(map[string]*State),
		transitions: make(map[string][]*Transition),
	}
}

func (f *FSM) AddState(state *State) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if _, exists := f.states[state.Name]; exists {
		return fmt.Errorf("state %s already exists", state.Name)
	}
	f.states[state.Name] = state
	return nil
}

func (f *FSM) AddTransition(t *Transition) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if _, exists := f.states[t.From]; !exists {
		return fmt.Errorf("from state %s does not exist", t.From)
	}
	if _, exists := f.states[t.To]; !exists {
		return fmt.Errorf("to state %s does not exist", t.To)
	}
	f.transitions[t.From] = append(f.transitions[t.From], t)
	return nil
}

func (f *FSM) Trigger(ctx context.Context, entity Entity, event EventType) error {
	f.mu.RLock()
	currentState := entity.GetState()
	transitions, exists := f.transitions[currentState]
	f.mu.RUnlock()

	if !exists {
		return fmt.Errorf("no transitions from state %s", currentState)
	}

	for _, t := range transitions {
		if t.Event != event {
			continue
		}

		if t.Guard != nil {
			ok, err := t.Guard(ctx, entity)
			if err != nil {
				return fmt.Errorf("guard failed: %w", err)
			}
			if !ok {
				continue
			}
		}

		f.mu.RLock()
		currentStateObj := f.states[currentState]
		targetStateObj := f.states[t.To]
		f.mu.RUnlock()

		if currentStateObj.OnExit != nil {
			if err := currentStateObj.OnExit(ctx, entity); err != nil {
				return fmt.Errorf("onExit failed: %w", err)
			}
		}

		if t.Action != nil {
			if err := t.Action(ctx, entity); err != nil {
				return fmt.Errorf("action failed: %w", err)
			}
		}

		entity.SetState(t.To)

		if targetStateObj.OnEnter != nil {
			if err := targetStateObj.OnEnter(ctx, entity); err != nil {
				return fmt.Errorf("onEnter failed: %w", err)
			}
		}

		return nil
	}

	return fmt.Errorf("no valid transition for event %v from state %s", event, currentState)
}

func (f *FSM) GetState(name string) (*State, bool) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	state, exists := f.states[name]
	return state, exists
}

var credentialFSM *FSM
var initCredentialFSMOnce sync.Once

func GetCredentialFSM() *FSM {
	initCredentialFSMOnce.Do(func() {
		credentialFSM = buildCredentialFSM()
	})
	return credentialFSM
}

func buildCredentialFSM() *FSM {
	fsm := NewFSM("credential_availability")

	fsm.AddState(&State{Name: "ready"})
	fsm.AddState(&State{Name: "cooling"})
	fsm.AddState(&State{Name: "rate_limited"})
	fsm.AddState(&State{Name: "unreachable"})
	fsm.AddState(&State{Name: "suspended", IsTerminal: true})
	fsm.AddState(&State{Name: "auth_failed"})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventFailureAuth,
		To:    "auth_failed",
	})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventFailureQuota,
		To:    "suspended",
	})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventFailureRateLimit,
		To:    "rate_limited",
	})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventFailureNetwork,
		To:    "unreachable",
	})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventFailureTimeout,
		To:    "unreachable",
	})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventFailureUpstreamDown,
		To:    "unreachable",
	})

	fsm.AddTransition(&Transition{
		From:  "cooling",
		Event: EventSuccess,
		To:    "ready",
	})

	fsm.AddTransition(&Transition{
		From:  "rate_limited",
		Event: EventSuccess,
		To:    "ready",
	})

	fsm.AddTransition(&Transition{
		From:  "unreachable",
		Event: EventSuccess,
		To:    "ready",
	})

	fsm.AddTransition(&Transition{
		From:  "auth_failed",
		Event: EventSuccess,
		To:    "ready",
	})

	fsm.AddTransition(&Transition{
		From:  "ready",
		Event: EventManualSuspend,
		To:    "suspended",
	})

	fsm.AddTransition(&Transition{
		From:  "suspended",
		Event: EventManualEnable,
		To:    "ready",
	})

	return fsm
}
