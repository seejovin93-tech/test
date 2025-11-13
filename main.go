package main

import (
	"encoding/json"
	"log"
	"net/http"
)

func main() {
	// Register the health route
	http.HandleFunc("/health", healthHandler)

	// Register the tasks route
	http.HandleFunc("/tasks", tasksHandler)

	// Log a message indicating the server is running
	log.Println("Listening on :8080...")

	// Start the server on port 8080
	log.Fatal(http.ListenAndServe(":8080", nil))
}

// healthHandler handles requests to the /health endpoint.
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}
