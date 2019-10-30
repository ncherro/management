.PHONY: run
run: clean-output setup
	docker run -it --rm \
		-v $(shell pwd):/app \
		-e JIRA_USERNAME=${JIRA_USERNAME} \
		-e JIRA_PASSWORD=${JIRA_PASSWORD} \
		-e JIRA_BASE_URL=${JIRA_BASE_URL} \
		-e JIRA_CACHE_FILE=/app/cache/cache.txt \
		team-velocity:latest

.PHONY: build
build:
	docker build -t team-velocity .

.PHONY: build-no-cache
build-no-cache:
	docker build --no-cache -t team-velocity .

.PHONY: setup
setup:
	mkdir -p output

.PHONY: clean-output
clean-output:
	rm -Rf output
