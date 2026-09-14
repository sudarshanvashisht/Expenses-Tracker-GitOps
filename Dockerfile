# STAGE 1 - Build the JAR ( java application runtime) using maven
FROM maven:3.8.3-openjdk-17 AS builder

WORKDIR /app

COPY . .

RUN mvn clean install -DskipTests=true

#STAGE 2 -  EXECUTE JAR FILE FROM THE ABOVE STAGE 
FROM eclipse-temurin:17-jre-alpine 

WORKDIR /app

COPY --from=BUILDER /app/target/*.jar /app/expenseapp.jar

CMD ["java","-jar","expenseapp.jar"]
