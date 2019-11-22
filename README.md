# JMH benchmark runner

Universal JMH benchmark runner for any given project.

- It installs all the project modules in the local Maven repository;
- it creates a new Maven project containing just the benchmarks and sets the dependencies needed to compile;
- it builds a benchmark jar;
- it runs all the benchmarks

This script produces:

- a log file for debugging;
- a json files with the benchmark results.

By default, all the output files will be saved in the working directory. The script will overwrite the benchmark results file, while it will append new lines to the log file.

## Before running
This script works on Linux (tested on Arch Linux). Since it is uses some OS-specific commands, it could not work on Windows/MacOS.

Requirements:

- JDK (any);
- Maven;
- Ruby (version 2.6);
- Ruby gem nokogiri (version 1.10.4) (`gem install nokogiri`).

## Run
Usage: `ruby run-benchmarks.rb {project-root} [options]`.

Example: `ruby run-benchmarks.rb commons-csv --dep=javax.annotation:javax.annotation-api:1.3.1`

Available options:

- `--dep={dependencies}`: comma-separated list of additional dependencies. The format should be `{group-id}:{artifact-id}:{version}` (e.g., `javax.annotation:javax.annotation-api:1.3.1`);
- `--resources={name}`: which resource folder should be used. By default, the one in `test` is used. Should refer to one of the folders in the `main` folder of the module containing benchmarks;
- `--java={version}`: sets the default Java version to use if no version is found in the pom (11 by default);
- `--jmh-folder={path}`: sets the output directory;
- `--rm={path}`: comma-separated list of files. Removes the specified file before building. The path should be relative to the source folder (e.g., "it/unimol/TestClass.java").
