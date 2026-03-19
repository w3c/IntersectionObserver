SHELL=/bin/bash -o pipefail
.PHONY: local remote deploy

remote: index.bs
	@ (HTTP_STATUS=$$(curl https://www.w3.org/publications/spec-generator/ \
	                       --output index.html \
	                       --write-out "%{http_code}" \
	                       --header "Accept: text/plain, text/html" \
	                       -F type=bikeshed-spec \
	                       -F die-on=warning \
	                       -F md-Text-Macro="COMMIT-SHA LOCAL COPY" \
	                       -F file=@index.bs) && \
	[[ "$$HTTP_STATUS" -eq "200" ]]) || ( \
		echo ""; cat index.html; echo ""; \
		rm -f index.html; \
		exit 22 \
	);

local: index.bs
	bikeshed spec index.bs index.html --md-Text-Macro="COMMIT-SHA LOCAL COPY"
