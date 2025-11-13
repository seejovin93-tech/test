package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
)

// Task struct represents a task
type Task struct {
	ID   int    `json:"id"`
	Text string `json:"text"`
	Done bool   `json:"done"`
}

var tasks = []Task{}
var nextID = 1

// tasksHandler manages task routes (GET, POST, PUT, DELETE)
func tasksHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	switch r.Method {
	case http.MethodGet:
		// Fetch all tasks
		_ = json.NewEncoder(w).Encode(tasks)

	case http.MethodPost:
		// Create a new task
		var in struct {
			Text string `json:"text"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.Text == "" {
			http.Error(w, `{"error":"invalid input"}`, http.StatusBadRequest)
			return
		}
		t := Task{ID: nextID, Text: in.Text, Done: false}
		nextID++
		tasks = append(tasks, t)
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(t)

	case http.MethodPut:
		// Update an existing task
		var in struct {
			Done bool `json:"done"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			http.Error(w, `{"error":"invalid input"}`, http.StatusBadRequest)
			return
		}
		idStr := r.URL.Query().Get("id")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			http.Error(w, `{"error":"invalid id"}`, http.StatusBadRequest)
			return
		}
		for i := range tasks {
			if tasks[i].ID == id {
				tasks[i].Done = in.Done
				_ = json.NewEncoder(w).Encode(tasks[i])
				return
			}
		}
		http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)

	case http.MethodDelete:
		// Delete a task
		idStr := r.URL.Query().Get("id")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			http.Error(w, `{"error":"invalid id"}`, http.StatusBadRequest)
			return
		}
		log.Printf("Attempting to delete task with ID: %d", id)
		for i := range tasks {
			if tasks[i].ID == id {
				// Delete the task
				tasks = append(tasks[:i], tasks[i+1:]...)
				// Log success and return the response
				log.Printf("Task with ID: %d deleted successfully.", id)
				// Send a success message with 200 OK instead of 204 No Content
				w.WriteHeader(http.StatusOK) // 200 OK
				_ = json.NewEncoder(w).Encode(map[string]string{"message": "task deleted successfully"})
				return
			}
		}
		http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)

	default:
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
	}
}
