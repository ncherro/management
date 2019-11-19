.PHONY: run
run: clean-output setup
	docker run -it --rm \
		-v $(shell pwd):/app \
		-e JIRA_EMAIL=${JIRA_EMAIL} \
		-e JIRA_API_KEY=${JIRA_API_KEY} \
		-e JIRA_BASE_URL=${JIRA_BASE_URL} \
		update-issues:latest

.PHONY: build
build:
	docker build -t update-issues .

.PHONY: build-no-cache
build-no-cache:
	docker build --no-cache -t update-issues .

.PHONY: setup
setup:
	mkdir -p output

.PHONY: clean-output
clean-output:
	rm -Rf output
