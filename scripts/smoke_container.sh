#!/bin/bash

# 1. Check if the health endpoint is working
echo "=== HEALTH | HTTP 200 ==="
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health | grep -q "200" && echo '{"ok":true}' || echo "Health check failed!"

# 2. Test GET request to fetch tasks (pre-clean)
echo "=== GET (pre-clean) | HTTP 200 ==="
curl -s http://localhost:8080/tasks

# 3. POST a new task
echo "=== POST /tasks | HTTP 201 ==="
curl -s -X POST -H "Content-Type: application/json" -d '{"text":"demo"}' http://localhost:8080/tasks

# 4. GET the tasks list after posting
echo "=== GET /tasks (after POST) | HTTP 200 ==="
curl -s http://localhost:8080/tasks

# 5. PUT request to mark the task as done
echo "=== PUT /tasks?id=1 | HTTP 200 ==="
curl -s -X PUT -H "Content-Type: application/json" -d '{"done":true}' http://localhost:8080/tasks?id=1

# 6. GET the tasks list after marking the task as done
echo "=== GET /tasks (after PUT) | HTTP 200 ==="
curl -s http://localhost:8080/tasks

# 7. DELETE the task
echo "=== DELETE /tasks?id=1 | HTTP 204 ==="
curl -s -X DELETE http://localhost:8080/tasks?id=1

# 8. Final GET should return empty list
echo "=== GET /tasks (final) | HTTP 200 ==="
curl -s http://localhost:8080/tasks
