#!/bin/bash

# Function to display the help message
show_help() {
    echo "Usage: $0 [options] <namespace>"
    echo
    echo "Options:"
    echo "  -a, --all                  Use the default search pattern for logs."
    echo "  -e, --error                Select the 'error' log level pattern to search."
    echo "  -w, --warn                 Select the 'warn' log level pattern to search."
    echo "  -h, --http                 Select the 'http' log level pattern to search."
    echo "  -f, --file <filename.md>   Specify the output Markdown filename for the report."
    echo "  -s, --search <pattern>     Specify a custom search pattern."
    echo "      --rg-args '<args>'     Provide custom 'rg' (ripgrep) arguments."
    echo
    echo "Description:"
    echo "  Search Kubernetes pod logs for specified patterns and compile results into a Markdown report."
    echo "  Custom 'rg' arguments can be passed with --rg-args for more advanced search options."
    echo
    echo "Examples:"
    echo "  $0 --error --file error_report.md my_namespace"
    echo "  $0 --all --rg-args '--ignore-case --follow' my_namespace"
    echo "  $0 -s 'custom pattern or regex' my_namespace"
    echo
}

# Check if no arguments were provided
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

declare -r DEFAULT_PATTERN="error|warn|fatal"
declare markdown_file=""
declare search_pattern=""
declare namespace=""
declare rg_custom_args=""

process_logs() {
    local log_pattern=$1
    local log_output

    if [[ -n $markdown_file ]]; then
        printf '```\n' >>"$markdown_file"
        log_output=$(rg $RG_OPTIONS $rg_custom_args -e "$log_pattern")
        printf "%s\n" "$log_output" >>"$markdown_file"
        printf '```\n' >>"$markdown_file"
    else
        rg $RG_OPTIONS $rg_custom_args -e "$log_pattern"
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all)
            search_pattern="$DEFAULT_PATTERN"
            shift
            ;;
        -e|--error)
            search_pattern="error"
            shift
            ;;
        -w|--warn)
            search_pattern="warn"
            shift
            ;;
        -h|--http)
            search_pattern="\b(404|403|500|502|503|504)\b"
            shift
            ;;
        -f|--file)
            markdown_file="$2"
            shift 2
            ;;
        -s|--search)
            search_pattern="$2"
            shift 2
            ;;
        --rg-args)
            rg_custom_args="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z $namespace ]]; then
                namespace="$1"
            else
                echo "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z $namespace ]]; then
	echo "Namespace is required. Use --help for usage information."
	exit 1
fi

# Declare and set the default rg options here to include potentially empty custom args without breaking the command.
declare -r RG_OPTIONS="--smart-case --follow --multiline --multiline-dotall -A 3 -B 2 -C 2 $rg_custom_args"

if [[ -n $markdown_file ]]; then
	printf "# Logs from Namespace: %s\n\n" "$namespace" >"$markdown_file"
	if [[ -n $search_pattern ]]; then
		printf "## Search Pattern Used\n\n" >>"$markdown_file"
		printf "`ripgrep` filter applied: \`%s\` with custom arguments: \`%s\`\n\n" "$search_pattern" "$rg_custom_args" >>"$markdown_file"
	else
		printf "## Search Pattern Used\n\n" >>"$markdown_file"
		printf "Full logs are shown without a specific `ripgrep` filter.\n\n" >>"$markdown_file"
	fi
fi

kubectl get pods -n "$namespace" --no-headers | awk '{print $1}' | while IFS= read -r pod; do
	log_prefix="Pod: $pod in Namespace: $namespace"
	echo -e "\e[32m$log_prefix\e[0m"

	if [[ -n $markdown_file ]]; then
		printf "## %s\n" "$log_prefix" >>"$markdown_file"
	fi

	readarray -t containers <<< "$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}')"
	for container in "${containers[@]}"; do
		echo "Container: $container"

		if [[ -n $markdown_file ]]; then
			printf "### Container: %s\n" "$container" >>"$markdown_file"
		fi

		if [[ -n $search_pattern ]]; then
			kubectl logs "$pod" -n "$namespace" -c "$container" | process_logs "$search_pattern"
		else
			if [[ -n $markdown_file ]]; then
				printf "No valid search pattern specified. Showing full logs.\n" >>"$markdown_file"
				kubectl logs "$pod" -n "$namespace" -c "$container" >>"$markdown_file"
			else
				echo "No valid search pattern specified. Showing full logs."
				kubectl logs "$pod" -n "$namespace" -c "$container"
			fi
		fi
	done
done
