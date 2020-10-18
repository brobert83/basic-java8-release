# Basic release tool for a Java 8 package including a push to Maven Central 
![Build and push to Dockerhub](https://github.com/brobert83/basic-java8-release/workflows/Build%20and%20push%20to%20Dockerhub/badge.svg)
![Docker Image Size (tag)](https://img.shields.io/docker/image-size/robertbaboi/basic-java8-release/latest)
![Apache License, Version 2.0, January 2004](https://img.shields.io/github/license/apache/maven.svg?label=License)

Published here: https://hub.docker.com/r/robertbaboi/basic-java8-release

The purpose of this container is to perform a "Release" of a Java 8 package built with Maven and push it to Maven Central.

| Env Variable            | Default value                     | Required | Comments                   
|:-------------           |:--------------                    |:---------|------------------- 
| DEPLOY                  | yes                               |          | To skip `mvn deploy` just override this with anything other than `yes`
| RELEASE_TYPE            | PATCH                             |          | Must be PATCH, MINOR or MAJOR (case insensitive)                     
| GITHUB_REPO             |                                   |  YES     |                    
| GITHUB_BRANCH           | master                            |          |                    
| GITHUB_USERNAME         |                                   |  YES     |                    
| GITHUB_EMAIL            |                                   |  YES     |                    
| GITHUB_TOKEN_FILE       | /work/secrets/github_token        |          |                    
| SIGNING_KEY_FILE        | /work/secrets/signingkey.asc      |          |                    
| GPG_KEY_NAME_FILE       | /work/secrets/gpg_keyname         |          |                    
| GPG_KEY_PASSPHRASE_FILE | /work/secrets/gpg_key_passphrase  |          |                    
| SONATYPE_USERNAME_FILE  | /work/secrets/sonatype_username   |          |                    
| SONATYPE_PASSWORD_FILE  | /work/secrets/sonatype_password   |          |                    

## Example
- The .m2 volume is mounted to avoid downloading the dependencies every time
- All the secrets are mounted into `/work/secrets`

```bash
docker run \
   -e GITHUB_REPO=github.com/${github_username}/${repo}.git \
   -e GITHUB_USERNAME=${github_username} \
   -e GITHUB_EMAIL=${github_email} \
   -v $(pwd)/../secrets:/work/secrets \
   -v $(pwd)/.m2:/root/.m2 \
  robertbaboi/basic-java8-release
```

# What does it do

1. Checkout the branch
2. Identify the release version(`${release_version}`) from `pom.xml` and calculate the next version(`${next_version}`) using the `RELEASE_TYPE` env var
    - it uses a simplified semantic versioning system:
        - the version **must match** this regular expression: `^([0-9]+)\.([0-9]+)\.([0-9]+)\-SNAPSHOT$`    
    - The calculus will increase the version part to which the env var refers to
        - For example, for version 2.5.1-SNAPSHOT, for all possible types, the next version will be:
            - RELEASE_TYPE=PATCH: `2.5.2`   
            - RELEASE_TYPE=MINOR: `2.6.0`
            - RELEASE_TYPE=MAJOR: `3.0.0`
3. Switch to a new branch named `RELEASE_${RELEASE_TYPE}_${release_version}`
4. Change version to the `${release_version}`        
5. Build
6. Deploy
    - runs:
        ```bash
        mvn clean deploy \
          -DskipTests=true \
          -Prelease \
          --settings /work/settings.xml \
          -Dgpg.executable=gpg2 \
          -Dgpg.keyname=${gpg_keyname} \
          -Dgpg.passphrase=${gpg_key_passphrase}
        ```
    - as long as pom.xml is properly configured this will push to Maven Central
    - notice that this command activates the `release` profile
7. Commit the version change
8. Tags with `v${release_version}`          
9. Updates the RELEASE_LOG.md file with a list of all commits in between this tag and the previous tag and commit
   - **This is somewhat fragile because any other tags other than release tags will dirty this**
10. Change the version to `${next_version}` and commit
11. Push the release branch
12. Push the tag

# Source Project Maven configuration

## SCM Section (replace the <<...>> placeholders)
```xml
<scm>
    <connection>scm:git:https://github.com/<<username>>/<<repo>>.git</connection>
    <developerConnection>scm:git:ssh://github.com/<<username>>/<<repo>>.git</developerConnection>
    <url>https://github.com/<<username>>/<<repo>></url>
    <tag>HEAD</tag>
</scm>
```

## Distribution Management Section
```xml
<distributionManagement>
   <snapshotRepository>
       <id>ossrh</id>
       <url>https://oss.sonatype.org/content/repositories/snapshots</url>
   </snapshotRepository>
   <repository>
       <id>ossrh</id>
       <url>https://oss.sonatype.org/service/local/staging/deploy/maven2</url>
   </repository>
</distributionManagement>
```

## The `release` build profile
```xml
<profile>     

   <id>release</id>

   <build>

       <plugins>

           <plugin>
               <groupId>org.apache.maven.plugins</groupId>
               <artifactId>maven-javadoc-plugin</artifactId>
               <version>3.0.0</version>
               <executions>
                   <execution>
                       <id>attach-javadocs</id>
                       <goals>
                           <goal>jar</goal>
                       </goals>
                   </execution>
               </executions>
           </plugin>

           <plugin>
               <groupId>org.apache.maven.plugins</groupId>
               <artifactId>maven-source-plugin</artifactId>
               <version>3.2.0</version>
               <executions>
                   <execution>
                       <id>attach-sources</id>
                       <goals>
                           <goal>jar</goal>
                       </goals>
                   </execution>
               </executions>
           </plugin>

           <plugin>
               <groupId>org.apache.maven.plugins</groupId>
               <artifactId>maven-gpg-plugin</artifactId>
               <version>1.6</version>
               <executions>
                   <execution>
                       <id>sign-artifacts</id>
                       <phase>verify</phase>
                       <goals>
                           <goal>sign</goal>
                       </goals>
                       <configuration>
                           <gpgArguments>
                               <arg>--pinentry-mode</arg>
                               <arg>loopback</arg>
                           </gpgArguments>
                       </configuration>
                   </execution>
               </executions>
           </plugin>

           <plugin>
               <groupId>org.sonatype.plugins</groupId>
               <artifactId>nexus-staging-maven-plugin</artifactId>
               <version>1.6.8</version>
               <extensions>true</extensions>
               <configuration>
                   <serverId>ossrh</serverId>
                   <nexusUrl>https://oss.sonatype.org/</nexusUrl>
                   <autoReleaseAfterClose>true</autoReleaseAfterClose>
               </configuration>
           </plugin>

       </plugins>

   </build> 

</profile>
```   
   
