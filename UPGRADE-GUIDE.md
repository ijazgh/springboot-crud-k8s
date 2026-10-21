# Spring Boot and Java upgrade

Target: Spring Boot 4.1.1, Java 26, Lombok 1.18.48.
Spring's current requirements document lists Java 26 as the highest supported JDK, so do not run this project with your installed JDK 27. Java 25 is an alternative if you prefer an LTS release; change both java.version and the Docker base image to 25 in that case.

## 1. IntelliJ settings

1. Open File > Project Structure > Project.
2. Select SDK > Download JDK, choose version 26 and an available OpenJDK distribution. Download it, select it as Project SDK, and use SDK default for the language level (no preview).
3. Under Project Structure > Modules, use Project SDK.
4. Open Settings > Build, Execution, Deployment > Build Tools > Maven > Runner. Set JRE to Project SDK (26).
5. Under Maven > Importing, select Project SDK (26) as JDK for importer if that field is shown.
6. Under Compiler > Annotation Processors, enable annotation processing and obtain processors from the project classpath. Maven also has its processor configured explicitly in pom.xml.
7. If IntelliJ shows errors for generated Lombok methods, ensure its Lombok plugin is installed and enabled. The plugin assists the editor; the Maven compiler configuration generates the actual methods.
8. Reload All Maven Projects from the Maven tool window.

For an external PowerShell build, set JAVA_HOME to the actual JDK 26 directory and put its bin directory first in PATH. Check both java -version and mvn -version: both should show 26. IntelliJ's Maven runner setting is independent of the terminal.

## 2. Code and dependency changes

| File | Change |
|---|---|
| pom.xml | Boot parent 4.1.1; Java release 26; current webmvc starter; com.mysql:mysql-connector-j; explicit Lombok annotation processor; test-only H2 |
| src/main/java/com/javatechie/crud/entity/Order.java | javax.persistence becomes jakarta.persistence; keep Lombok; nullable Integer ID for JSON requests without an ID; explicit MySQL IDENTITY IDs |
| src/main/resources/application.yml | Keep environment placeholders and local defaults; default database javatechie; remove MySQL5Dialect so Hibernate detects the current dialect; remove delayed connection failure |
| src/test/resources/application.yml | Use an isolated in-memory H2 database only during tests |
| src/test/java/com/javatechie/crud/OrderMappingTests.java | Verify JSON mapping, generated accessors, persisted field values, and JSON response fields |
| Dockerfile | Java 26 image matching compilation target |

Spring Boot manages compatible Spring, Hibernate, Jackson, JDBC driver and test-library versions. Do not add old manually pinned versions. Lombok is explicitly pinned consistently in the dependency and annotation processor. A provided Lombok dependency does not need to be packaged with the app.

The H2 tests verify mapping and JPA persistence, but do not prove MySQL authentication or existing-schema migration compatibility. Production still uses MySQL. Runtime configuration here retains the existing local tutorial authentication settings; production should use verified TLS.

## 3. Build and check Lombok

In IntelliJ's Maven goal field, run:

```text
clean install
```

Tests now use H2, so MySQL, Kubernetes port forwarding and DB environment variables are unnecessary for this build. Maven downloads the new dependencies on the first run.

From PowerShell in your project directory:

```powershell
javap -classpath target/classes com.javatechie.crud.entity.Order
```

The output must include getName(), setName(...), getQty(), setQty(...), getPrice(), and setPrice(...).

## 4. Existing MySQL table: run the one-time ID migration

Before deploying the upgraded application, open MySQL using the current MySQL pod name:

```powershell
kubectl get pods
kubectl exec -it <mysql-pod-name> -- mysql -u root -p
```

In MySQL:

```sql
USE javatechie;
SHOW CREATE TABLE orders_tbl;
ALTER TABLE orders_tbl MODIFY COLUMN id INT NOT NULL AUTO_INCREMENT;
SHOW CREATE TABLE orders_tbl;
```

Run the ALTER once if id is not already AUTO_INCREMENT. This retains existing rows, changes how future IDs are allocated, and may lock the table briefly. It assumes the original project's INT primary key. Do not use it unchanged if your table's id definition differs. New auto-increment IDs continue above the current maximum. Do not delete the PVC or hibernate_sequence table. Existing incorrect rows remain unchanged.

For a brand-new database, Hibernate creates the identity column automatically; the ALTER is unnecessary.

## 5. Build and deploy a distinct image

```powershell
docker build -t springboot-crud-k8s:boot4-java26 .
```

In app-deployment.yaml, set the container to:

```yaml
image: springboot-crud-k8s:boot4-java26
imagePullPolicy: IfNotPresent
```

Then:

```powershell
kubectl apply -f app-deployment.yaml
kubectl rollout status deployment/springboot-crud-deployment --timeout=180s
kubectl logs deployment/springboot-crud-deployment --tail=100
```

Look for the application startup-completed message and no database errors. Rebuilding the same image tag again requires restarting the deployment; use a new tag for each later build to make image selection unambiguous.

## 6. Verify in Postman

POST http://localhost:30905/orders with Content-Type: application/json and this body:

```json
{"name":"Watch","qty":2,"price":1499}
```

The response should contain an ID and all three values. GET the same URL, and in MySQL run SELECT * FROM javatechie.orders_tbl; to confirm persistence.

## Common dependency and setup errors

| Error | Check |
|---|---|
| release version 26 not supported | Maven Runner JRE and terminal JAVA_HOME must use JDK 26 |
| UnsupportedClassVersionError | The runtime/Docker image must use Java 26 too |
| package javax.persistence does not exist | Use jakarta.persistence imports in Order.java |
| MySQL5Dialect not found | Remove the old explicit dialect property |
| getName/setName not found, or response {} | Reload Maven, run clean install, verify javap output, rebuild Docker and deploy the new image |
| Cannot find mysql:mysql-connector-java | Use com.mysql:mysql-connector-j with the Boot-managed version |
| Public Key Retrieval is not allowed | Confirm the new application.yml is inside the rebuilt JAR/image and not overridden by another datasource URL |
| Could not resolve artifact | Check Maven Central connectivity, offline mode and proxy settings; reload Maven |
| Field id doesn't have a default value | Verify AUTO_INCREMENT on the existing MySQL table before using IDENTITY |

Sources: https://docs.spring.io/spring-boot/system-requirements.html ; https://projectlombok.org/setup/maven ; https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide
