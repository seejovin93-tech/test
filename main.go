package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"golang.org/x/time/rate"
)

// Task represents a single task item
type Task struct {
	ID    int    `json:"id"`
	Title string `json:"title"`
	Text  string `json:"text"`
	Done  bool   `json:"done"`
}

var tasks []Task
var nextID = 1

// Rate-limit middleware (correct: 5 req/s, burst 5)
func rateLimit(next http.Handler) http.Handler {
	// Use 5 tokens/second with a bucket of 5
	limiter := rate.NewLimiter(rate.Limit(5), 5)
	// Alternatively: limiter := rate.NewLimiter(rate.Every(200*time.Millisecond), 5)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !limiter.Allow() {
			http.Error(w, "Too Many Requests", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// CRUD handler for /tasks
func tasksHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	switch r.Method {
	case http.MethodGet:
		_ = json.NewEncoder(w).Encode(tasks)

	case http.MethodPost:
		// Accept either {"title": "..."} or {"text": "..."}
		var in struct {
			Title string `json:"title"`
			Text  string `json:"text"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			http.Error(w, `{"error":"invalid input"}`, http.StatusBadRequest)
			return
		}
		title := in.Title
		if title == "" {
			title = in.Text
		}
		t := Task{
			ID:    nextID,
			Title: title,
			Text:  title, // keep both populated for test compatibility
			Done:  false,
		}
		nextID++
		tasks = append(tasks, t)
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(t)

	case http.MethodPut:
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
		idStr := r.URL.Query().Get("id")
		id, err := strconv.Atoi(idStr)
		if err != nil {
			http.Error(w, `{"error":"invalid id"}`, http.StatusBadRequest)
			return
		}
		for i := range tasks {
			if tasks[i].ID == id {
				tasks = append(tasks[:i], tasks[i+1:]...)
				w.WriteHeader(http.StatusOK)
				_ = json.NewEncoder(w).Encode(map[string]string{"message": "task deleted successfully"})
				return
			}
		}
		http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)

	default:
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

// Must emit {"ok":true}\n to satisfy TestHealth
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

func main() {
	http.Handle("/tasks", rateLimit(http.HandlerFunc(tasksHandler)))
	http.HandleFunc("/health", healthHandler)

	log.Println("Server starting on port 8080...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("could not start server: %s\n", err)
	}
}
