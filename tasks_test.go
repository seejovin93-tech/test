package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestTasks(t *testing.T) {
	// Test POST /tasks (creating a task)
	req := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader(`{"title":"Test Task"}`)) // Correct request body
	rr := httptest.NewRecorder()
	tasksHandler(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("status=%d want=%d", rr.Code, http.StatusCreated)
	}

	// Decode the response and check if the task is created
	var createdTask Task
	err := json.NewDecoder(rr.Body).Decode(&createdTask)
	if err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if createdTask.Title != "Test Task" {
		t.Fatalf("created task title=%s want=%s", createdTask.Title, "Test Task")
	}

	// Additional tests for GET, PUT, DELETE can be added here
}
