package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

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
	req := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader(`{"text":"Test Task"}`))
	rr := httptest.NewRecorder()
	tasksHandler(rr, req)

	req = httptest.NewRequest(http.MethodPut, "/tasks?id=1", strings.NewReader(`{"done":true}`))
	rr = httptest.NewRecorder()
	tasksHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status=%d want=%d", rr.Code, http.StatusOK)
	}

	var updatedTask Task
	err := json.NewDecoder(rr.Body).Decode(&updatedTask)
	if err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if !updatedTask.Done {
		t.Fatalf("expected task to be marked as done, got %v", updatedTask.Done)
	}
}

func TestDeleteTask(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader(`{"text":"Test Task"}`))
	rr := httptest.NewRecorder()
	tasksHandler(rr, req)

	req = httptest.NewRequest(http.MethodDelete, "/tasks?id=1", nil)
	rr = httptest.NewRecorder()
	tasksHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("status=%d want=%d", rr.Code, http.StatusOK)
	}

	var response map[string]string
	err := json.NewDecoder(rr.Body).Decode(&response)
	if err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if response["message"] != "task deleted successfully" {
		t.Fatalf("expected message 'task deleted successfully', got %s", response["message"])
	}
}
