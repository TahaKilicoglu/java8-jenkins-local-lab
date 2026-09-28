FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /build
COPY pom.xml ./
COPY src ./src
RUN mvn -B -ntp clean verify

FROM eclipse-temurin:8-jre
WORKDIR /app
COPY --from=build /build/target/loadtest-demo-1.0.0.jar /app/app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
