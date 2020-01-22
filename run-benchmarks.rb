#!/usr/bin/ruby
VERSION = '0.1.8'

require "nokogiri"
require "set"
require "optparse"

ARCHETYPE_POM = <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>{{groupId}}</groupId>
    <artifactId>jmh-generic-runner</artifactId>
    <version>{{version}}</version>
    <packaging>jar</packaging>

    <name>JMH Generic runner</name>

    <dependencies>
        <dependency>
            <groupId>org.openjdk.jmh</groupId>
            <artifactId>jmh-core</artifactId>
            <version>${jmhrbautobenchmark.jmh.version}</version>
        </dependency>
        <dependency>
            <groupId>org.openjdk.jmh</groupId>
            <artifactId>jmh-generator-annprocess</artifactId>
            <version>${jmhrbautobenchmark.jmh.version}</version>
            <scope>provided</scope>
        </dependency>

        {{dependencies}}
    </dependencies>

    <properties>
        {{properties}}
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <jmhrbautobenchmark.jmh.version>{{jmh-version}}</jmhrbautobenchmark.jmh.version>
        <jmhrbautobenchmark.javac.target>{{java-version}}</jmhrbautobenchmark.javac.target>
        <jmhrbautobenchmark.uberjar.name>benchmarks</jmhrbautobenchmark.uberjar.name>
    </properties>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.8.0</version>
                <configuration>
                    <compilerVersion>${jmhrbautobenchmark.javac.target}</compilerVersion>
                    <source>${jmhrbautobenchmark.javac.target}</source>
                    <target>${jmhrbautobenchmark.javac.target}</target>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.2.1</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <finalName>${jmhrbautobenchmark.uberjar.name}</finalName>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>org.openjdk.jmh.Main</mainClass>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ServicesResourceTransformer"/>
                            </transformers>
                            <filters>
                                <filter>
                                    <artifact>*:*</artifact>
                                    <excludes>
                                        <exclude>META-INF/*.SF</exclude>
                                        <exclude>META-INF/*.DSA</exclude>
                                        <exclude>META-INF/*.RSA</exclude>
                                    </excludes>
                                </filter>
                            </filters>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
        <pluginManagement>
            <plugins>
                <plugin>
                    <artifactId>maven-clean-plugin</artifactId>
                    <version>2.5</version>
                </plugin>
                <plugin>
                    <artifactId>maven-deploy-plugin</artifactId>
                    <version>2.8.1</version>
                </plugin>
                <plugin>
                    <artifactId>maven-install-plugin</artifactId>
                    <version>2.5.1</version>
                </plugin>
                <plugin>
                    <artifactId>maven-jar-plugin</artifactId>
                    <version>2.4</version>
                </plugin>
                <plugin>
                    <artifactId>maven-javadoc-plugin</artifactId>
                    <version>2.9.1</version>
                </plugin>
                <plugin>
                    <artifactId>maven-resources-plugin</artifactId>
                    <version>2.6</version>
                </plugin>
                <plugin>
                    <artifactId>maven-site-plugin</artifactId>
                    <version>3.3</version>
                </plugin>
                <plugin>
                    <artifactId>maven-source-plugin</artifactId>
                    <version>2.2.1</version>
                </plugin>
                <plugin>
                    <artifactId>maven-surefire-plugin</artifactId>
                    <version>2.17</version>
                </plugin>
            </plugins>
        </pluginManagement>
    </build>

    <repositories>
        {{repositories}}
    </repositories>
</project>
EOF

JMH_BASE = "art-jmh-env"
GOOD_BUILD_STRING = "[INFO] BUILD SUCCESS"
LOG_EXT = ".log"
MAVEN_BIN = ENV["MVN_BIN"]   || raise("You need to set the MVN_BIN environment variable to run the script.")
JAVA_HOME = ENV["JAVA_HOME"] || raise("You need to set the JAVA_HOME environment variable to run the script.")

$files_to_remove         = []
$additional_dependencies = []
$additional_properties   = []
$src_name                = "main"
$resources_name          = "test"
$java_version            = "11"
$jmh_version             = nil
$jmh_result_folder       = Dir.pwd
$testing_mode            = false
$maven_options           = []

OptionParser.new do |opts|
    opts.banner = "JMH benchmark runner, version #{VERSION}\nUsage: run-benchmarks.rb [options] directory"
    
    opts.on("-r", "--rm [FILES]", "comma-separated list of files. Removes the specified file before building. The path should be relative to the source folder (e.g., 'it/unimol/TestClass.java')") do |files|
        $files_to_remove = files.split(",")
    end
    
    opts.on("-d", "--dep [DEPENDENCIES]", "comma-separated list of additional dependencies. The format should be {group-id}:{artifact-id}:{version} (e.g., 'javax.annotation:javax.annotation-api:1.3.1')") do |deps|
        $additional_dependencies = deps.split(",")
    end
    
    opts.on("-D", "--prop [PROPERTIES]", "comma-separated list of additional properties. The format should be '{property}={value}'") do |props|
        $additional_properties = props.split(",")
    end
    
    opts.on("-R", "--resources [FOLDER]", "which resource folder should be used. By default, the one in test is used. Should refer to one of the folders in the main folder of the module containing benchmarks") do |resources|
        $resources_name = resources
    end
    
    opts.on("-j", "--java [VERSION]", "sets the default Java version to use if no version is found in the pom (11 by default)") do |java|
        $java_version = java
    end
    
    opts.on("-J", "--jmh [JMH]", "sets the default JMH version to use if no version is found in the pom (raises an error by default)") do |jmh|
        $jmh_version = jmh
    end
    
    opts.on("-o", "--jmh-folder [FOLDER]", "sets the output directory") do |jmh|
        $jmh_result_folder = jmh
    end
    
    opts.on("-M", "--maven-options [OPTIONS]", "semicolon-separated list of commands to pass to the maven build") do |options|
        $maven_options = options.split(";")
    end
    
    opts.on("-v", "--version", "shows the current version") do |v|
        puts "Version #{VERSION}"
        exit 0
    end
    
    opts.on("-T", "--test", "runs in testing mode (does not run the benchmarks)") do |testing|
        $testing_mode = true
    end
    
    opts.on("-h", "--help", "shows this help") do |help|
        warn opts
        exit 0
    end
end.parse!

$maven_options = $maven_options.join(" ")

DIRECTORY = ARGV[0]

unless DIRECTORY
    warn "Please, specify the build directory."
    exit -1
end

class Shell
    @@log = nil
    
    def self.log_file=(log)
        @@log = log
    end
    
    def self.run(command)
        append_to_log = @@log ? " 2>> \"#{@@log}\"" : ""
        self.log "\t$> #{command}#{append_to_log}"
        return `#{command}#{append_to_log}`
    end
    
    def self.log(string, print_time=true)
        string.gsub!('"', " ")
        warn string
        
        string.split("\n").each do |message|
            time = print_time ? "[" + Time.now.strftime("%Y.%m.%d|%H:%M:%S.%L") + "] " : ""
            message.gsub!("$", "\\$")
            system("echo \"#{time}#{message}\" >> #{@@log}") if @@log
        end
    end
    
    def self.separator(char="-")
        self.log char*60, false
    end
end

class Property
    attr_accessor   :name
    attr_accessor   :value
    
    def initialize(name, value)
        @name = name
        @value = value
    end
    
    def eql?(oth)
        return @name == oth.name
    end
    
    def hash
        @name.hash
    end
    
    def to_s
        "<#@name>#@value</#@name>"
    end
end

class Repository
    attr_accessor   :id
    attr_accessor   :url
    attr_accessor   :layout
    
    def initialize
        @id = nil
        @url = nil
        @layout = nil
    end
    
    def eql?(oth)
        return @id == oth.id && @url == oth.url
    end
    
    def hash
        @id.hash + @url.hash
    end
    
    def to_s
        id_part     = "<id>#@id</id>"
        url_part    = "<url>#@url</url>"
        layout_part = @layout ? "<layout>#@layout</layout>" : ""
        
        return "<repository>" + id_part + url_part + layout_part + "</repository>"
    end
end

class Dependency
    attr_accessor   :group_id
    attr_accessor   :artifact_id
    attr_accessor   :version
    attr_accessor   :type
    
    @@mvn_path = nil
    
    def initialize
        @@mvn_path = Shell.run("#{MAVEN_BIN} --batch-mode help:evaluate -Dexpression=settings.localRepository | grep -v '\[INFO\]'").chomp.strip unless @@mvn_path
        
        @group_id = ""
        @artifact_id = ""
        @version = ""
        @type = ""
    end
    
    def exist?
        folder = File.join(@@mvn_path, @group_id.gsub('.', '/'), @artifact_id.gsub('.', '/'), @version)
        return FileTest.exist?(folder) && (Dir.glob(File.join(folder, "*.jar")).size > 0 || Dir.glob(File.join(folder, "*.pom")).size > 0)
    end
    
    def jmh?
        return @group_id == "org.openjdk.jmh"
    end
    
    def valid?
        return ["pom", "jar", ""].include?(@type) && @group_id != "" && @artifact_id != "" && @version != ""
    end
    
    def to_s
        "<dependency><groupId>#@group_id</groupId><artifactId>#@artifact_id</artifactId><version>#@version</version>#{ @type != "" ? "<type>#@type</type>" : ""}</dependency>"
    end
    
    def eql?(oth)
        return @group_id == oth.group_id && @artifact_id == oth.artifact_id && @version == oth.version
    end
    
    def hash
        return @group_id.hash + @artifact_id.hash + @version.hash
    end
    
    def readable_string
        "#@group_id:#@artifact_id:#@version" + (@type != "" ? ":#@type" : "")
    end
end

class JMH
    @@jars = []
    
    def self.build(java_version, jmh_version, project_group_id, project_version, dependencies, properties, repositories=[])
        instance_pom = ARCHETYPE_POM.clone
        instance_pom.gsub!("{{java-version}}", java_version)
        instance_pom.gsub!("{{jmh-version}}", jmh_version)
        instance_pom.gsub!("{{dependencies}}", dependencies.join("\n"))
        instance_pom.gsub!("{{properties}}", properties.join("\n"))
        instance_pom.gsub!("{{version}}", project_version)
        instance_pom.gsub!("{{groupId}}", project_group_id)
        instance_pom.gsub!("{{repositories}}", repositories.join("\n"))
        
        File.open("pom.xml", "w") do |f|
            f.write instance_pom
        end
        
        result = Shell.run "#{MAVEN_BIN} --batch-mode clean package -DskipTests"
        
        JMH.set_jars(["target/benchmarks.jar"])
        
        return result
    end
    
    def self.set_jars(jars)
        @@jars = jars
    end
    
    def self.run
        i = ""
        @@jars.each do |jar|
            Shell.run "java -jar \"#{jar}\" -rf json -rff \"#$jmh_result_folder/#{Project.name}#{i}.json\""
            i = (i.to_i + 1).to_s
        end
    end
end

class Project
    def self.each_pom_path
        Dir.glob("**/pom.xml").each do |pom|
            next if pom.include?(JMH_BASE)
            yield pom
        end
    end
    
    def self.name
        DIRECTORY.split("/")[-1]
    end

    def self.each_pom
        Project.each_pom_path do |pom|
            xml = Nokogiri::XML(File.read(pom))
            xml.remove_namespaces!
            yield xml
        end
    end

    def self.get_pom_dependencies
        dependencies = []
        Project.each_pom do |xml|
            group_id    = xml.xpath("/project/groupId").text
            artifact_id = xml.xpath("/project/artifactId").text
            version     = xml.xpath("/project/version").text
            type        = xml.xpath("/project/packaging").text
            
            parent_group_id    = xml.xpath("/project/parent/groupId").text
            parent_artifact_id = xml.xpath("/project/parent/artifactId").text
            parent_version     = xml.xpath("/project/parent/version").text
            
            group_id    = group_id == "" ? parent_group_id : group_id
            version     = version == ""  ? parent_version  : version
            
            test_dependencies = xml.xpath("/project/dependencies/dependency[scope='test']") + xml.xpath("//dependencies/dependency[scope='test']")
            test_dependencies.each do |dependency|
                test_dependency = Dependency.new
                test_dependency.group_id    = dependency.xpath("groupId").text
                test_dependency.artifact_id = dependency.xpath("artifactId").text
                test_dependency.version     = dependency.xpath("version").text
                
                if test_dependency.valid? && !test_dependency.jmh?
                    Shell.log "\tImporting test dependency #{test_dependency.readable_string}"
                    dependencies << test_dependency
                end
            end
            
            dependency = Dependency.new
            dependency.group_id = group_id
            dependency.artifact_id = artifact_id
            dependency.version = version
            dependency.type = type
            
            if dependency.valid? && dependency.exist?
                Shell.log "\tImporting project dependency #{dependency.readable_string}"
                dependencies << dependency
            end
        end
        
        return dependencies
    end
    
    def self.get_repositories
        repositories = Set[]
        
        Project.each_pom do |xml|
            xml.xpath("/project/repositories/repository").each do |repository|
                repo = Repository.new
                repo.id     = repository.xpath("id").text
                repo.url    = repository.xpath("url").text
                repo.layout = repository.xpath("layout").text
                
                repositories << repo
            end
        end
        
        return repositories.to_a
    end
    
    def self.get_version
        versions = Set[]
        Project.each_pom do |xml|
            version = xml.xpath("/project/version").text            
            versions << version
        end
        
        if versions.size == 1
            return versions.to_a[0]
        elsif versions.size == 0
            Shell.log("\tNo project version specified. Falling back to 1.0.")
            return "1.0"
        else
            version = versions.to_a.sort[-1]
            Shell.log("\tToo many project versions specified: #{versions}. Using the latest one: #{version}.")
            return version
        end
    end
    
    def self.get_group_id
        groups = Set[]
        Project.each_pom do |xml|
            parent_group_id = xml.xpath("/project/parent/groupId").text
            group_id        = xml.xpath("/project/groupId").text
            
            groups << parent_group_id   if parent_group_id && parent_group_id.strip != ""
            groups << group_id          if group_id        && group_id.strip != ""
        end
        
        if groups.size == 1
            return groups.to_a[0]
        elsif groups.size == 0
            Shell.log("Cannot get the group id. This should never happen. Aborting.")
            exit -1
        else
            group_id = groups.to_a.sort[-1]
            Shell.log("\tToo many project group ids specified: #{groups}. Using the last one: #{group_id}.")
            return group_id
        end
    end
    
    def self.get_jmh_version    
        jmh_versions = Set[]
        
        Project.each_pom do |xml|
            jmh_dependency_versions = xml.xpath("//dependencies/dependency[groupId='org.openjdk.jmh' and artifactId='jmh-core']/version")
            jmh_dependency_versions.each do |version|
                jmh_versions << version.text
            end
        end
        
        jmh_versions.delete_if { |v| v.strip == "" }
            
        if jmh_versions.size == 0
            return nil
        elsif jmh_versions.size > 1
            Shell.log "There were many JMH versions found: #{jmh_versions.sort.join(",")}. Using the latest one."
            return jmh_versions.sort[-1]
        else
            return jmh_versions.to_a[0]
        end
    end
    
    def self.paths_to_benchmarks
        Dir.glob("**/benchmarks.jar")
    end

    def self.get_properties
        all_properties = []
        mapping = {}
        Project.each_pom do |xml|
            properties = xml.xpath("/project/properties/*")
            properties.each do |property|
                mapping[property.name] = Set[] unless mapping[property.name]
                
                unless property.text.start_with?("${")
                    mapping[property.name] << property.text
                end
            end
        end
                    
        # Makes sure that there is exactly a property with a given name
        mapping.each do |name, values|
            values = values.to_a
            if values.size == 1
                Shell.log "\tImporting property #{name} => #{values[0]}"
                all_properties << Property.new(name, values[0])
            end
        end
        
        return all_properties
    end
    
    def self.get_additional_properties
        properties = []
        
        $additional_properties.each do |property|
            name, value = property.split("=")
            properties << Property.new(name, value)
        end
        
        return properties
    end

    def self.get_java_version    
        java_versions = Set[]
        
        Project.each_pom do |xml|
            compile_plugin = xml.xpath("/project/build/plugins/plugin[artifactId='maven-compiler-plugin']/configuration/source")
            if compile_plugin.size > 0
                java_versions << compile_plugin[0].text
            end
        end
        
        if java_versions.size == 0
            Shell.log "There was no Java version found in any POM file in the target project. Using Java #$java_version"
            return $java_version
        elsif java_versions.size > 1
            Shell.log "There were many Java versions found: #{java_versions.sort.join(",")}. Using the latest one."
            return java_versions.sort[-1]
        else
            return java_versions.to_a[0]
        end
    end

    def self.each_benchmark
        Dir.glob("**/*.java").each do |src|
            content = File.read(src)
            if content.include?("@Benchmark") ||
                    content.include?("import org.openjdk.jmh.annotations.Benchmark;") ||
                    content.include?("@org.openjdk.jmh.annotations.Benchmark")
                yield src
            end
        end
    end

    def self.get_source_directory(file)
        content = File.read(file)
        package = content.scan(/package ([^;]+);/).flatten[0].split(".").join("/")
        base = file.sub(File.join("java", package, File.basename(file)), "")
        return base
    end
    
    def self.get_additional_dependencies
        dependencies = []
        
        $additional_dependencies.each do |string_dependency|
            dependency = Dependency.new
            dependency.group_id, dependency.artifact_id, dependency.version = string_dependency.split(":")
            Shell.log "\tImporting additional dependency #{dependency.readable_string}"
            
            dependencies << dependency
        end
        
        return dependencies
    end
end

class Phases
    def self.reset_folder
        Dir.chdir(DIRECTORY) do
            if FileTest.exist? JMH_BASE
                Shell.log "Removing previously created #{JMH_BASE} folder"
                Shell.run "rm -r \"#{JMH_BASE}\""
            end
        end
    end
    
    def self.build_project
        Dir.chdir(DIRECTORY) do
            Shell.log "Running maven build..."
            build_result = Shell.run "#{MAVEN_BIN} --batch-mode clean install -DskipTests #$maven_options"

            unless build_result.include? GOOD_BUILD_STRING
                Shell.log build_result
                Shell.log "The maven build failed."
                exit -1
            end
            
            Shell.run "mkdir -p \"#{JMH_BASE}/src/#$src_name/java\""
        end
    end
    
    def self.prepare_benchmarks
        Dir.chdir(DIRECTORY) do
            source_directories = Set[]
            Project.each_benchmark do |benchmark_file|
                source_directories << Project.get_source_directory(benchmark_file)
            end
            
            Shell.log "Source directories: #{source_directories.to_a.to_s}"
            source_directories.each do |src|
                real_src = File.join(src, "*")
                real_dst = File.join(JMH_BASE, "src", $src_name)
                
                Shell.run "cp -R #{real_src.gsub(' ', '\ ')} #{real_dst.gsub(' ', '\ ')}"
                
                resources_src = File.join(src, "resources")
                
                if FileTest.exist? resources_src
                    resources_dst = File.join(JMH_BASE, "src", $resources_name)
                    Shell.run "mkdir -p \"#{resources_dst}\""
                    
                    Shell.run "cp -R #{resources_src.gsub(' ', '\ ')} #{resources_dst.gsub(' ', '\ ')}"
                end
            end
        end
    end
    
    def self.run_benchmarks(run=true)
        Dir.chdir(DIRECTORY) do
            available_benchmarks = Project.paths_to_benchmarks
            if available_benchmarks.size > 0
                Shell.log "Using available uberjars for benchmarks: #{available_benchmarks}"
                JMH.set_jars(available_benchmarks)
                if run
                    Shell.log "Running benchmarks..."
                    JMH.run
                else
                    Shell.log "Skipping benchmark run."
                end
            else
                $files_to_remove.each do |to_remove|
                    path = File.join(JMH_BASE, "src", $src_name, "java", to_remove)
                    Shell.log "Forcing removal of #{path}"
                    Shell.run "rm \"#{path}\""
                end
                
                java_version        = Project.get_java_version
                jmh_version         = Project.get_jmh_version
                project_group_id    = Project.get_group_id
                project_version     = Project.get_version
                repositories        = Project.get_repositories
                
                properties   = Project.get_properties + Project.get_additional_properties
                dependencies = Project.get_pom_dependencies + Project.get_additional_dependencies
                dependencies.uniq!
                
                unless jmh_version
                    if $jmh_version
                        Shell.log "There was no JMH found in any POM file in the target project. Using the one specified in the command line."
                        jmh_version = $jmh_version
                    else
                        Shell.log "There was no JMH found in any POM file in the target project."
                        Shell.log "Aborting."
                        exit -1
                    end
                end
                
                Shell.log "Using JMH version #{jmh_version}"
                Dir.chdir JMH_BASE do
                    Shell.log "Building benchmarks"
                    result = JMH.build java_version, jmh_version, project_group_id, project_version, dependencies, properties, repositories
                    unless result.include? GOOD_BUILD_STRING
                        Shell.log result
                        Shell.log "Could not build benchmarks"
                        exit -1
                    end
                    
                    if run
                        Shell.log "Running benchmarks..."
                        result = JMH.run
                    else
                        Shell.log "Skipping benchmark run."
                    end
                end
            end
        end
    end
end

Shell.log_file = File.join($jmh_result_folder, Project.name + LOG_EXT)

Shell.log "Version #{VERSION}"
Shell.log "<!><!><!> The program is running in testing mode. No benchmark will be executed. <!><!><!>" if $testing_mode
Shell.separator "#"
Shell.log "Files to remove: #$files_to_remove"
Shell.log "Additional dependencies: #$additional_dependencies"
Shell.log "Resources folder: #$resources_name"
Shell.log "Default Java version (if not specified): #$java_version"
Shell.log "Default JMH version (if not specified): #$jmh_version" if $jmh_version
Shell.log "Additional properties: #$additional_properties"

Shell.separator
Shell.log "Starting procedure"
Phases.reset_folder

Shell.separator
Shell.log "Project build started"
Phases.build_project

Shell.separator
Shell.log "Benchmark preparation started"
Phases.prepare_benchmarks

Shell.separator
Shell.log "Benchmark build and run started"
Phases.run_benchmarks(!$testing_mode)

Shell.separator
Shell.log "All done"
