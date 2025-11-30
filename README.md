# Poor man's PiTest

Read the story here: https://meirz.net/2025/11/29/poor-mans-pitest/

## Usage:

Usage: ./runPPIT.sh [-h] [-s] [-b branch] [-m module]

Options:
-h Show this help message and exit
-s Skip 'mvn clean install' step
-b Target branch for git diff (default: origin/main)
-m Run only specified module (must be affected by changes)

This script will:
1. Analyze modified Java files (current branch vs origin/main)
2. Group classes by Maven submodule
3. Run 'mvn clean install' on affected modules (unless -s)
4. Execute PIT mutation coverage on each module
5. Generate summary report with timings

All details are logged into PPIT.log

## Dependencies:

In the root pom add pitest plugin:
```
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>1.21.0</version>
</plugin>
```

In order to support jUnit 5 you need to add `pitest-junit5-plugin`

**Note:** below example is for multi-module project that will have mix of modules using jUnit4 and jUnit5. If your project is only using jUnit5 you can add the dependency directly to the pitest-maven plugin configuration and remove isJUnit5Module() function and associated code in the script. Otherwise, just add the profile as shown below.
```
<profile>
    <id>pitest-junit5</id>
    <build>
        <plugins>
            <plugin>
                <groupId>org.pitest</groupId>
                <artifactId>pitest-maven</artifactId>
                <dependencies>
                    <dependency>
                        <groupId>org.pitest</groupId>
                        <artifactId>pitest-junit5-plugin</artifactId>
                        <version>1.2.3</version>
                    </dependency>
                </dependencies>
            </plugin>
        </plugins>
    </build>
</profile>
```

## Note:

Script is developer for windows (under git bash), if you are using Linux or Mac you might need to adjust some commands.