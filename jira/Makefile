.PHONY: run
run:
	docker run -it --rm \
		-v $(shell pwd)/cache:/tmp/jira-cache \
		-v $(shell pwd)/data:/app/data \
		-v $(shell pwd)/output:/tmp/output \
		-e JIRA_USERNAME=${JIRA_USERNAME} \
		-e JIRA_PASSWORD=${JIRA_PASSWORD} \
		-e JIRA_CACHE_FILE=/tmp/jira-cache/cache.txt \
		team-velocity:latest

.PHONY: build
build:
	docker build -t team-velocity .

.PHONY: build-no-cache
build-no-cache:
	docker build --no-cache -t team-velocity .
