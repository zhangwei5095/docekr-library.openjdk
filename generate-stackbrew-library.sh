#!/bin/bash
set -eu

declare -A aliases=(
	[8-jdk]='jdk latest'
	[8-jre]='jre'
)
defaultType='jdk'

image="${1:-openjdk}"

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

cat <<-EOH
# this file is generated via https://github.com/docker-library/openjdk/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/openjdk.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

aliases() {
	local javaVersion="$1"; shift
	local javaType="$1"; shift
	local fullVersion="$1"; shift
	local variant="${1:-}" # optional

	local bases=( $fullVersion )
	if [ "${fullVersion%-*}" != "$fullVersion" ]; then
		bases+=( ${fullVersion%-*} ) # like "8u40-b09
	fi
	if [ "$javaVersion" != "${fullVersion%-*}" ]; then
		bases+=( $javaVersion )
	fi

	local versionAliases=()
	for base in "${bases[@]}"; do
		versionAliases+=( "$base-$javaType" )
		if [ "$javaType" = "$defaultType" ]; then
			versionAliases+=( "$base" )
		fi
	done

	# generate "openjdkPrefix" before adding aliases ("latest") so we avoid tags like "openjdk-latest"
	local openjdkPrefix=( "${versionAliases[@]/#/openjdk-}" )

	# add aliases and the prefixed versions (so the silly prefix versions come dead last)
	versionAliases+=( ${aliases[$javaVersion-$javaType]:-} )

	if [ "$image" = 'java' ]; then
		# add "openjdk" prefixes (these should stay very last so their use is properly discouraged)
		versionAliases+=( "${openjdkPrefix[@]}" )
	fi

	if [ "$variant" ]; then
		versionAliases=( "${versionAliases[@]/%/-$variant}" )
		versionAliases=( "${versionAliases[@]//latest-/}" )
	fi

	echo "${versionAliases[@]}"
}

for version in "${versions[@]}"; do
	commit="$(dirCommit "$version")"

	javaVersion="$version" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-$javaType}" # "6"

	fullVersion="$(git show "$commit":"$version/Dockerfile" | awk '$1 == "ENV" && $2 == "JAVA_VERSION" { gsub(/~/, "-", $3); print $3; exit }')"

	echo
	cat <<-EOE
		Tags: $(join ', ' $(aliases "$javaVersion" "$javaType" "$fullVersion"))
		GitCommit: $commit
		Directory: $version
	EOE

	for variant in alpine; do
		[ -f "$version/$variant/Dockerfile" ] || continue

		commit="$(dirCommit "$version/$variant")"

		fullVersion="$(git show "$commit":"$version/$variant/Dockerfile" | awk '$1 == "ENV" && $2 == "JAVA_VERSION" { gsub(/~/, "-", $3); print $3; exit }')"

		echo
		cat <<-EOE
			Tags: $(join ', ' $(aliases "$javaVersion" "$javaType" "$fullVersion" "$variant"))
			GitCommit: $commit
			Directory: $version/$variant
		EOE
	done
done
