.PHONY: run
run: clean-output setup
	docker run -it --rm \
		-v $(shell pwd):/app \
		-e JIRA_EMAIL=${JIRA_EMAIL} \
		-e JIRA_API_KEY=${JIRA_API_KEY} \
		-e JIRA_BASE_URL=${JIRA_BASE_URL} \
		generate-gantt:latest

.PHONY: build
build:
	docker build -t generate-gantt .

.PHONY: build-no-cache
build-no-cache:
	docker build --no-cache -t generate-gantt .

.PHONY: setup
setup:
	mkdir -p output

.PHONY: clean-output
clean-output:
	rm -Rf output
