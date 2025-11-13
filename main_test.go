package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

var mu sync.Mutex

func TestHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rr := httptest.NewRecorder()
	healthHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status=%d want=%d", rr.Code, http.StatusOK)
	}
	want := "{\"ok\":true}\n"
	if rr.Body.String() != want {
		t.Fatalf("body=%q want=%q", rr.Body.String(), want)
	}
}

func TestUpdateTask(t *testing.T) {
	// Reset state for this test
	mu.Lock()
	tasks = []Task{}
	nextID = 1
	mu.Unlock()

	// Create a task first
	reqCreate := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader(`{"text":"Test Task"}`))
	rrCreate := httptest.NewRecorder()
	tasksHandler(rrCreate, reqCreate)

	if rrCreate.Code != http.StatusCreated {
		t.Fatalf("create task status=%d want=%d", rrCreate.Code, http.StatusCreated)
	}

	// Now, update the task
	reqUpdate := httptest.NewRequest(http.MethodPut, "/tasks?id=1", strings.NewReader(`{"done":true}`))
	rrUpdate := httptest.NewRecorder()
	tasksHandler(rrUpdate, reqUpdate)

	if rrUpdate.Code != http.StatusOK {
		t.Fatalf("update task status=%d want=%d", rrUpdate.Code, http.StatusOK)
	}

	var updatedTask Task
	err := json.NewDecoder(rrUpdate.Body).Decode(&updatedTask)
	if err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if !updatedTask.Done {
		t.Fatalf("expected task to be marked as done, got %v", updatedTask.Done)
	}
}
