FROM eclipse-temurin:26-jdk
WORKDIR /app
COPY target/springboot-crud-k8s.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
