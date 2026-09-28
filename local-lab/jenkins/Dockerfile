FROM docker:28-cli AS docker-cli
FROM jenkins/jenkins:lts-jdk21
USER root
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx
RUN apt-get update && apt-get install -y --no-install-recommends curl git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# setup-and-publish.ps1 exports the Windows trusted roots here (certificates only).
COPY certs/ /usr/local/share/ca-certificates/local-lab/
RUN set -eu; \
    update-ca-certificates; \
    cp "$JAVA_HOME/lib/security/cacerts" /opt/local-lab-cacerts; \
    for cert in /usr/local/share/ca-certificates/local-lab/windows-*.crt; do \
        [ -f "$cert" ] || continue; \
        alias="lab-$(basename "$cert" .crt)"; \
        "$JAVA_HOME/bin/keytool" -importcert -noprompt -trustcacerts \
            -alias "$alias" -file "$cert" \
            -keystore /opt/local-lab-cacerts -storepass changeit >/dev/null; \
    done
ENV JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStore=/opt/local-lab-cacerts -Djavax.net.ssl.trustStorePassword=changeit"
USER jenkins
COPY --chown=jenkins:jenkins jenkins.yaml /usr/share/jenkins/ref/jenkins.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/jenkins.yaml
RUN jenkins-plugin-cli --plugins workflow-aggregator git credentials-binding configuration-as-code job-dsl
