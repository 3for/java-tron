#!/bin/bash
#############################################################################
#
#                    GNU LESSER GENERAL PUBLIC LICENSE
#                        Version 3, 29 June 2007
#
#  Copyright (C) [2007] [TRON Foundation], Inc. <https://fsf.org/>
#  Everyone is permitted to copy and distribute verbatim copies
#  of this license document, but changing it is not allowed.
#
#
#   This version of the GNU Lesser General Public License incorporates
# the terms and conditions of version 3 of the GNU General Public
# License, supplemented by the additional permissions listed below.
#
# You can find java-tron at https://github.com/tronprotocol/java-tron/
#
##############################################################################

# Build FullNode config
FULL_NODE_DIR="FullNode"
FULL_NODE_CONFIG_DIR="config"
# config file
FULL_NODE_CONFIG_PRIVATE_NET="private_net_config.conf"
DEFAULT_FULL_NODE_CONFIG='config.conf'
JAR_NAME="FullNode.jar"
FULL_START_OPT=''

# Github
GITHUB_BRANCH='master'
GITHUB_CLONE_TYPE='HTTPS'
GITHUB_REPOSITORY=''
GITHUB_REPOSITORY_HTTPS_URL='https://github.com/tronprotocol/java-tron.git'
GITHUB_REPOSITORY_SSH_URL='git@github.com:tronprotocol/java-tron.git'
FULL_NODE_CONFIG_MAIN_NET_BASE_URL='https://raw.githubusercontent.com/tronprotocol/java-tron'
FULL_NODE_CONFIG_PRIVATE_NET_URL='https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/private_net_config.conf'

# Shell option
ALL_OPT_LENGTH=$#
# Start service option
MAX_STOP_TIME=60
# Modify this option to allow the minimum memory to be started, unit MB
ALLOW_MIN_MEMORY=8192

# JVM option
MAX_DIRECT_MEMORY=1g
JVM_MS=4g
JVM_MX=4g
IS_BACKUP_GC_LOG=true

SPECIFY_MEMORY=0
STOP=false
UPGRADE=false

# Rebuild manifest
REBUILD_MANIFEST=true
REBUILD_DIR="$PWD/output-directory/database"
REBUILD_MANIFEST_SIZE=0
REBUILD_BATCH_SIZE=80000

# Download and upgrade
DOWNLOAD=false
RELEASE_URL='https://github.com/tronprotocol/java-tron/releases'
RELEASE_FULL_NODE_ASSET='FullNode.jar'
RELEASE_GPG_KEYSERVER='hkps://keyserver.ubuntu.com'
RELEASE_GPG_PRIMARY_FINGERPRINT='07B23298AEA4E006BD9A42DE785FB96D2C7C3CA5'
QUICK_START=false
CLONE_BUILD=false

if [[ $GITHUB_CLONE_TYPE == 'HTTPS' ]]; then
  GITHUB_REPOSITORY=$GITHUB_REPOSITORY_HTTPS_URL
else
  GITHUB_REPOSITORY=$GITHUB_REPOSITORY_SSH_URL
fi

# Determine the Java command to use to start the JVM.
if [ -z "$JAVA_HOME" ]; then
  javaExecutable="`which javac`"
  if [ -n "$javaExecutable" ] && ! [ "`expr \"$javaExecutable\" : '\([^ ]*\)'`" = "no" ]; then
    # readlink(1) is not available as standard on Solaris 10.
    readLink=`which readlink`
    if [ ! `expr "$readLink" : '\([^ ]*\)'` = "no" ]; then
      if $darwin ; then
        javaHome="`dirname \"$javaExecutable\"`"
        javaExecutable="`cd \"$javaHome\" && pwd -P`/javac"
      else
        javaExecutable="`readlink -f \"$javaExecutable\"`"
      fi
      javaHome="`dirname \"$javaExecutable\"`"
      javaHome=`expr "$javaHome" : '\(.*\)/bin'`
      JAVA_HOME="$javaHome"
      export JAVA_HOME
    fi
  fi
fi

if [ -z "$JAVACMD" ] ; then
  if [ -n "$JAVA_HOME"  ] ; then
    if [ -x "$JAVA_HOME/jre/sh/java" ] ; then
      # IBM's JDK on AIX uses strange locations for the executables
      JAVACMD="$JAVA_HOME/jre/sh/java"
    else
      JAVACMD="$JAVA_HOME/bin/java"
    fi
  else
    JAVACMD="`which java`"
  fi
fi

if [ ! -x "$JAVACMD" ] ; then
  echo "Error: JAVA_HOME is not defined correctly." >&2
  echo "  We cannot execute $JAVACMD" >&2
  exit 1
fi

if [ -z "$JAVA_HOME" ] ; then
  echo "Warning: JAVA_HOME environment variable is not set."
fi

backupGCLog() {
  local maxFile=5
  local gcLogDir=logs/gc_logs/
  if [ ! -d "$gcLogDir" ];then
    mkdir -p 'logs/gc_logs'
  fi

  if [ -f 'gc.log' ]; then
    echo '[info] backup gc.log'
    local dateformat=`date "+%Y-%m-%d_%H-%M-%S"`
    tar -czvf gc.log_$dateformat'.tar.gz' gc.log
    mv gc.log_$dateformat'.tar.gz' $gcLogDir
    rm -rf gc.log

    # checking the number of backups
    local currentDirCount=`ls -l $gcLogDir | grep "gc.log*" | wc -l`
    if [ $currentDirCount -gt $maxFile ]; then
      local oldFileSize=`expr $currentDirCount - $maxFile`
      local oldGcLogFiles=(`ls -1 $gcLogDir |head -n $oldFileSize`)
    fi

    for fileName in ${oldGcLogFiles[@]}; do
      rm -rf $gcLogDir$fileName
    done
  fi
}

getLatestReleaseVersion() {
  full_node_version=$(git ls-remote --refs --tags --sort=-version:refname \
    "$GITHUB_REPOSITORY" 'refs/tags/GreatVoyage-*' | \
    awk -F/ 'NR == 1 { print $3; exit }')
  if [[ -n $full_node_version ]]; then
   echo $full_node_version
  else
   echo ''
  fi
}

checkVersion() {
 github_release_version=$(`echo getLatestReleaseVersion`)
 if [[ -n $github_release_version ]]; then
  echo "info: github latest version: $github_release_version"
  echo $github_release_version
 else
    echo 'info: not getting the latest version'
    exit
 fi
}

upgrade() {
  local latest_version
  latest_version=$(getLatestReleaseVersion)
  echo "info: latest version: $latest_version"
  if [[ -n $latest_version ]]; then
    if ! installVerifiedReleaseArtifact \
      "$latest_version" "$RELEASE_FULL_NODE_ASSET" "$JAR_NAME" true; then
      echo "info: failed to download and verify version $latest_version" >&2
      return 1
    fi
    echo "info: download and verification of version $latest_version succeeded"
  else
    echo 'info: nothing to upgrade' >&2
    return 1
  fi
}

downloadTo() {
  local url=$1
  local file_name=$2
  local output_dir
  local output_name
  local temporary_file

  if [[ "$url" != https://* ]]; then
    echo "info: refusing non-HTTPS download URL: $url" >&2
    return 1
  fi
  if [[ -L "$file_name" ]]; then
    echo "info: refusing to replace symbolic link: $file_name" >&2
    return 1
  fi
  if [[ -e "$file_name" && ! -f "$file_name" ]]; then
    echo "info: download destination is not a regular file: $file_name" >&2
    return 1
  fi

  output_dir=$(dirname -- "$file_name")
  output_name=$(basename -- "$file_name")
  if [[ ! -d "$output_dir" ]]; then
    echo "info: download destination directory does not exist: $output_dir" >&2
    return 1
  fi
  if ! temporary_file=$(mktemp "$output_dir/.${output_name}.tmp.XXXXXX"); then
    echo "info: failed to create a temporary download file in $output_dir" >&2
    return 1
  fi

  if ! type curl >/dev/null 2>&1; then
    rm -f -- "$temporary_file"
    echo 'info: curl is required for strict HTTPS downloads' >&2
    return 1
  fi

  # -q must be curl's first argument so a user-level .curlrc cannot enable
  # insecure TLS behavior. Restrict both the initial URL and every redirect to
  # HTTPS; wget's --https-only does not provide this guarantee for redirects.
  echo "curl -q -fsSL --proto =https --proto-redir =https --tlsv1.2 -o $temporary_file $url"
  if ! curl -q -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
    -o "$temporary_file" "$url"; then
    rm -f -- "$temporary_file"
    return 1
  fi

  if [[ ! -s "$temporary_file" ]]; then
    echo "info: downloaded file is empty: $url" >&2
    rm -f -- "$temporary_file"
    return 1
  fi
  if [[ -L "$file_name" ]] || [[ -e "$file_name" && ! -f "$file_name" ]]; then
    echo "info: download destination changed to a non-regular file: $file_name" >&2
    rm -f -- "$temporary_file"
    return 1
  fi
  if ! mv -f -- "$temporary_file" "$file_name"; then
    rm -f -- "$temporary_file"
    return 1
  fi
}

verifyReleaseSignature() {
  local artifact_file=$1
  local signature_file=$2

  if ! type gpg >/dev/null 2>&1; then
    echo 'info: gpg is required to verify java-tron release artifacts' >&2
    return 1
  fi

  (
    local fingerprint_output
    local gpg_home
    local primary_count
    local verification_status

    if ! gpg_home=$(mktemp -d "${TMPDIR:-/tmp}/java-tron-gpg.XXXXXX"); then
      echo 'info: failed to create a temporary GPG home' >&2
      exit 1
    fi
    trap 'rm -rf -- "$gpg_home"' EXIT
    chmod 700 "$gpg_home" || exit 1

    if ! gpg --homedir "$gpg_home" --no-options --batch --no-tty --quiet \
      --keyserver "$RELEASE_GPG_KEYSERVER" \
      --recv-keys "$RELEASE_GPG_PRIMARY_FINGERPRINT"; then
      echo "info: failed to import the pinned java-tron release signing key from $RELEASE_GPG_KEYSERVER" >&2
      exit 1
    fi

    if ! fingerprint_output=$(gpg --homedir "$gpg_home" --no-options --batch --no-tty \
      --with-colons --fingerprint --fingerprint \
      "$RELEASE_GPG_PRIMARY_FINGERPRINT" 2>/dev/null); then
      echo 'info: failed to inspect the java-tron release signing key' >&2
      exit 1
    fi
    primary_count=$(printf '%s\n' "$fingerprint_output" | awk -F: \
      -v expected="$RELEASE_GPG_PRIMARY_FINGERPRINT" \
      '$1 == "fpr" && $10 == expected { count++ } END { print count + 0 }')
    if [[ "$primary_count" -ne 1 ]]; then
      echo 'info: imported java-tron release key does not match the pinned primary fingerprint' >&2
      exit 1
    fi

    if ! verification_status=$(gpg --homedir "$gpg_home" --no-options --batch --no-tty \
      --status-fd 1 --verify "$signature_file" "$artifact_file" 2>/dev/null); then
      echo "info: release signature verification failed for $artifact_file" >&2
      exit 1
    fi
    if ! printf '%s\n' "$verification_status" | awk \
      -v primary="$RELEASE_GPG_PRIMARY_FINGERPRINT" '
        $1 == "[GNUPG:]" && ($2 == "BADSIG" || $2 == "ERRSIG" ||
          $2 == "NO_PUBKEY" || $2 == "REVKEYSIG" || $2 == "EXPKEYSIG" ||
          $2 == "EXPSIG") {
          rejected = 1
        }
        $1 == "[GNUPG:]" && $2 == "VALIDSIG" {
          count++
          signing_primary = ($12 == "" ? $3 : $12)
          if (signing_primary == primary) {
            valid++
          }
        }
        END { exit !(rejected == 0 && count == 1 && valid == 1) }
      '; then
      echo 'info: release signature was not made by the pinned java-tron primary key' >&2
      exit 1
    fi
  )
}

installVerifiedReleaseArtifact() {
  local release_version=$1
  local release_asset=$2
  local destination=$3
  local backup_existing=${4:-false}

  if [[ ! "$release_version" =~ ^GreatVoyage-[A-Za-z0-9._-]+$ ]]; then
    echo "info: invalid java-tron release tag: $release_version" >&2
    return 1
  fi
  case "$release_asset" in
  FullNode.jar | ArchiveManifest.jar)
    ;;
  *)
    echo "info: unsupported java-tron release artifact: $release_asset" >&2
    return 1
    ;;
  esac

  (
    local artifact_temporary_file=''
    local backup_file
    local backup_temporary_file=''
    local destination_dir
    local destination_name
    local signature_temporary_file=''

    if [[ -L "$destination" ]] || [[ -e "$destination" && ! -f "$destination" ]]; then
      echo "info: release destination is not a regular file: $destination" >&2
      exit 1
    fi
    destination_dir=$(dirname -- "$destination")
    destination_name=$(basename -- "$destination")
    if [[ ! -d "$destination_dir" ]]; then
      echo "info: release destination directory does not exist: $destination_dir" >&2
      exit 1
    fi

    artifact_temporary_file=$(mktemp \
      "$destination_dir/.${destination_name}.artifact.XXXXXX") || exit 1
    trap 'rm -f -- "$artifact_temporary_file" "$signature_temporary_file" "$backup_temporary_file"' EXIT
    signature_temporary_file=$(mktemp \
      "$destination_dir/.${destination_name}.signature.XXXXXX") || exit 1

    if ! downloadTo \
      "$RELEASE_URL/download/$release_version/$release_asset" \
      "$artifact_temporary_file"; then
      echo "info: failed to download $release_asset for $release_version" >&2
      exit 1
    fi
    if ! downloadTo \
      "$RELEASE_URL/download/$release_version/$release_asset.sig" \
      "$signature_temporary_file"; then
      echo "info: failed to download $release_asset.sig for $release_version" >&2
      exit 1
    fi
    if ! verifyReleaseSignature \
      "$artifact_temporary_file" "$signature_temporary_file"; then
      exit 1
    fi

    if [[ -L "$destination" ]] || [[ -e "$destination" && ! -f "$destination" ]]; then
      echo "info: release destination changed to a non-regular file: $destination" >&2
      exit 1
    fi
    if [[ "$backup_existing" == true && -f "$destination" ]]; then
      backup_file="${destination}_bak"
      if [[ -L "$backup_file" ]] || [[ -e "$backup_file" && ! -f "$backup_file" ]]; then
        echo "info: release backup destination is not a regular file: $backup_file" >&2
        exit 1
      fi
      backup_temporary_file=$(mktemp \
        "$destination_dir/.${destination_name}_bak.XXXXXX") || exit 1
      if ! cp -p -- "$destination" "$backup_temporary_file"; then
        echo "info: failed to back up $destination" >&2
        exit 1
      fi
      if [[ -L "$backup_file" ]] || [[ -e "$backup_file" && ! -f "$backup_file" ]]; then
        echo "info: release backup destination changed to a non-regular file: $backup_file" >&2
        exit 1
      fi
      if ! mv -f -- "$backup_temporary_file" "$backup_file"; then
        echo "info: failed to install release backup: $backup_file" >&2
        exit 1
      fi
      backup_temporary_file=''
    fi

    if ! mv -f -- "$artifact_temporary_file" "$destination"; then
      echo "info: failed to install verified release artifact: $destination" >&2
      exit 1
    fi
    if [[ -L "$destination" || ! -f "$destination" || ! -s "$destination" ]]; then
      echo "info: installed release artifact is not a non-empty regular file: $destination" >&2
      exit 1
    fi
    artifact_temporary_file=''
    echo "info: verified $release_asset with the pinned java-tron release signing key"
  )
}

mkdirFullNode() {
  if [ ! -d $FULL_NODE_DIR ]; then
    echo "info: create $FULL_NODE_DIR"
    mkdir $FULL_NODE_DIR
    $(cp $0 $FULL_NODE_DIR)
    cd $FULL_NODE_DIR
  elif [ -d $FULL_NODE_DIR ]; then
    cd $FULL_NODE_DIR
  fi
}

quickStart() {
  local full_node_version
  local main_net_config_url
  full_node_version=$(getLatestReleaseVersion)
  if [[ -n $full_node_version ]]; then
    if ! mkdirFullNode; then
      echo 'info: failed to prepare the FullNode release directory' >&2
      return 1
    fi
    echo "info: check latest version: $full_node_version"
    echo 'info: download config'
    main_net_config_url="$FULL_NODE_CONFIG_MAIN_NET_BASE_URL/$full_node_version/framework/src/main/resources/config.conf"
    if ! downloadTo "$main_net_config_url" 'config.conf'; then
      echo 'info: failed to download Mainnet config'
      exit 1
    fi

    echo "info: download $full_node_version"
    if ! installVerifiedReleaseArtifact \
      "$full_node_version" "$RELEASE_FULL_NODE_ASSET" "$JAR_NAME"; then
      echo "info: failed to download and verify $full_node_version" >&2
      return 1
    fi
  else
    echo 'info: not getting the latest version' >&2
    return 1
  fi
}

cloneCode() {
  if type git >/dev/null 2>&1; then
    git_clone=$(git clone -b $GITHUB_BRANCH $GITHUB_REPOSITORY)
    if [[ git_clone == 0 ]]; then
      echo 'info: git clone java-tron success'
    fi
  else
    echo 'info: no exists git, make sure the system can use the "git" command'
  fi
}

cloneBuild() {
  local currentPwd=$PWD
  echo 'info: clone java-tron'
  cloneCode

  echo 'info: build java-tron'
  cd java-tron
  sh gradlew clean build -x test
  if [[ $? == 0 ]];then
    cd $currentPwd
    mkdirFullNode
    cp '../java-tron/build/libs/FullNode.jar' $PWD
    cp '../java-tron/framework/src/main/resources/config.conf' $PWD
  else
    exit
  fi
}

normalizeJarPath() {
  local base_directory=${2:-$PWD}
  local jar_directory
  local jar_name
  local jar_path=$1

  if [[ "$jar_path" != /* ]]; then
    jar_path="$base_directory/$jar_path"
  fi
  jar_directory=$(dirname -- "$jar_path")
  jar_name=$(basename -- "$jar_path")
  if ! jar_directory=$(cd -- "$jar_directory" 2>/dev/null && pwd -P); then
    return 1
  fi
  if [[ "$jar_directory" == / ]]; then
    printf '/%s\n' "$jar_name"
  else
    printf '%s/%s\n' "$jar_directory" "$jar_name"
  fi
}

processWorkingDirectory() {
  local candidate_pid=$1
  local cwd_output
  local os
  local process_cwd
  local process_cwd_count

  os=$(uname)
  if [[ "$os" == Linux ]] || [[ "$os" == linux ]]; then
    if ! process_cwd=$(readlink "/proc/$candidate_pid/cwd" 2>/dev/null); then
      return 1
    fi
  elif [[ "$os" == Darwin ]]; then
    if ! type lsof >/dev/null 2>&1; then
      return 1
    fi
    if ! cwd_output=$(lsof -a -p "$candidate_pid" -d cwd -Fn 2>/dev/null); then
      return 1
    fi
    process_cwd_count=$(printf '%s\n' "$cwd_output" | awk '/^n/ { count++ } END { print count + 0 }')
    if [[ "$process_cwd_count" -ne 1 ]]; then
      return 1
    fi
    process_cwd=$(printf '%s\n' "$cwd_output" | awk '/^n/ { print substr($0, 2); exit }')
  else
    return 1
  fi

  if [[ ! -d "$process_cwd" ]]; then
    return 1
  fi
  (cd -- "$process_cwd" 2>/dev/null && pwd -P)
}

linuxProcessStartTokenFromStat() {
  local start_token
  local stat_fields
  local stat_line=$1

  # Field 2 (comm) is parenthesized and may itself contain spaces or closing
  # parentheses. Remove through the final ") " before selecting field 22,
  # which is field 20 in the remainder beginning with process state.
  stat_fields=${stat_line##*) }
  if [[ "$stat_fields" == "$stat_line" ]]; then
    return 1
  fi
  start_token=$(printf '%s\n' "$stat_fields" | awk '{ print $20; exit }')
  if [[ ! "$start_token" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  printf '%s\n' "$start_token"
}

processStartToken() {
  local candidate_pid=$1
  local os
  local start_output
  local start_token
  local stat_line

  os=$(uname)
  if [[ "$os" == Linux ]] || [[ "$os" == linux ]]; then
    if ! stat_line=$(<"/proc/$candidate_pid/stat"); then
      return 1
    fi
    if ! start_token=$(linuxProcessStartTokenFromStat "$stat_line"); then
      return 1
    fi
    printf 'linux:%s\n' "$start_token"
  elif [[ "$os" == Darwin ]]; then
    if ! start_output=$(ps -p "$candidate_pid" -o lstart=); then
      return 1
    fi
    if ! start_token=$(printf '%s\n' "$start_output" | awk '
      NF {
        count++
        $1 = $1
        token = $0
      }
      END {
        if (count != 1) {
          exit 1
        }
        print token
      }
    '); then
      return 1
    fi
    printf 'darwin:%s\n' "$start_token"
  else
    return 1
  fi
}

hasProcessStartToken() {
  local candidate_pid=$1
  local expected_token=$2
  local current_token

  if ! current_token=$(processStartToken "$candidate_pid"); then
    return 1
  fi
  [[ "$current_token" == "$expected_token" ]]
}

checkPid() {
  local candidate_jar
  local candidate_pid
  local candidate_path
  local candidate_working_directory
  local process_list
  local target_basename
  local target_path
  local -a matching_pids=()
  local -a uncertain_pids=()

  pid=''
  if ! target_path=$(normalizeJarPath "$JAR_NAME"); then
    echo "warn: cannot normalize jar path $JAR_NAME" >&2
    return 1
  fi
  if [[ "$target_path" =~ [[:space:]] ]]; then
    echo "warn: cannot safely inspect a jar path containing whitespace: $target_path" >&2
    return 1
  fi
  target_basename=$(basename -- "$target_path")
  if ! process_list=$(ps -ww -eo pid=,args=); then
    echo 'warn: failed to inspect running processes' >&2
    return 1
  fi

  while IFS=$'\t' read -r candidate_pid candidate_jar; do
    if [[ ! "$candidate_pid" =~ ^[0-9]+$ ]] || [[ -z "$candidate_jar" ]]; then
      continue
    fi
    if [[ "$candidate_jar" != /* ]]; then
      if [[ $(basename -- "$candidate_jar") != "$target_basename" ]]; then
        continue
      fi
      if candidate_working_directory=$(processWorkingDirectory "$candidate_pid") &&
         candidate_path=$(normalizeJarPath "$candidate_jar" "$candidate_working_directory"); then
        if [[ "$candidate_path" == "$target_path" ]]; then
          matching_pids+=("$candidate_pid")
        fi
      else
        uncertain_pids+=("$candidate_pid")
      fi
      continue
    fi
    if candidate_path=$(normalizeJarPath "$candidate_jar") &&
       [[ "$candidate_path" == "$target_path" ]]; then
      matching_pids+=("$candidate_pid")
    fi
  done < <(printf '%s\n' "$process_list" | awk '
    {
      process_pid = $1
      for (field = 2; field < NF; field++) {
        if ($field == "-jar") {
          printf "%s\t%s\n", process_pid, $(field + 1)
          break
        }
      }
    }
  ')

  if [[ ${#uncertain_pids[@]} -gt 0 ]]; then
    echo "warn: could not determine the working directory for a process using the relative jar name $target_basename" >&2
    echo "warn: confirm the intended PID and stop it manually: ${uncertain_pids[*]}" >&2
    return 1
  fi
  if [[ ${#matching_pids[@]} -gt 1 ]]; then
    echo "warn: multiple processes use the exact jar path $target_path; refusing to stop any process" >&2
    echo "warn: confirm the intended PID and stop it manually: ${matching_pids[*]}" >&2
    return 1
  fi
  if [[ ${#matching_pids[@]} -eq 1 ]]; then
    pid=${matching_pids[0]}
  fi
  return 0
}

stopService() {
  local count=0
  local target_start_token
  local target_pid

  if ! checkPid; then
    return 1
  fi
  if [[ -z "$pid" ]]; then
    echo "info: java-tron stop"
    return 0
  fi
  target_pid=$pid
  if ! target_start_token=$(processStartToken "$target_pid"); then
    echo "warn: cannot verify the start identity of java-tron process $target_pid; refusing to signal it" >&2
    return 1
  fi

  # Close the initial scan-to-signal window as far as a ps-based identity
  # check permits. Never switch to a replacement PID or process start identity.
  if ! checkPid; then
    return 1
  fi
  if [[ -z "$pid" ]]; then
    echo "info: java-tron stop"
    return 0
  fi
  if [[ "$pid" != "$target_pid" ]]; then
    echo "warn: the process using $JAR_NAME changed from PID $target_pid to PID $pid; refusing to signal the new process" >&2
    return 1
  fi
  if ! hasProcessStartToken "$target_pid" "$target_start_token"; then
    echo "warn: the start identity of java-tron PID $target_pid changed or could not be verified; refusing to signal it" >&2
    return 1
  fi
  if ! kill -15 "$target_pid"; then
    echo "warn: failed to stop java-tron process $target_pid" >&2
    return 1
  fi

  while [[ $count -lt $MAX_STOP_TIME ]]; do
    sleep 1
    if ! checkPid; then
      return 1
    fi
    if [[ -z "$pid" ]]; then
      echo "info: java-tron stop"
      return 0
    fi
    if [[ "$pid" != "$target_pid" ]]; then
      echo "warn: the process using $JAR_NAME changed from PID $target_pid to PID $pid; refusing to signal the new process" >&2
      return 1
    fi
    if ! hasProcessStartToken "$target_pid" "$target_start_token"; then
      echo "warn: the start identity of java-tron PID $target_pid changed or could not be verified; refusing to signal it" >&2
      return 1
    fi
    count=$((count + 1))
  done

  # Revalidate the exact JAR identity and original PID immediately before the
  # forceful signal so a replacement process is never selected during waiting.
  if ! checkPid; then
    return 1
  fi
  if [[ -z "$pid" ]]; then
    echo "info: java-tron stop"
    return 0
  fi
  if [[ "$pid" != "$target_pid" ]]; then
    echo "warn: the process using $JAR_NAME changed from PID $target_pid to PID $pid; refusing to signal the new process" >&2
    return 1
  fi
  if ! hasProcessStartToken "$target_pid" "$target_start_token"; then
    echo "warn: the start identity of java-tron PID $target_pid changed or could not be verified; refusing to force-stop it" >&2
    return 1
  fi
  if ! kill -9 "$target_pid"; then
    echo "warn: failed to force-stop java-tron process $target_pid" >&2
    return 1
  fi
  sleep 1
  if ! checkPid; then
    return 1
  fi
  if [[ -z "$pid" ]]; then
    echo "info: java-tron stop"
    return 0
  fi
  if [[ "$pid" != "$target_pid" ]]; then
    echo "warn: the process using $JAR_NAME changed from PID $target_pid to PID $pid after force-stop; refusing to signal the new process" >&2
    return 1
  fi
  if ! hasProcessStartToken "$target_pid" "$target_start_token"; then
    echo "warn: java-tron PID $target_pid now has a different start identity after force-stop" >&2
    return 1
  fi
  echo "warn: java-tron process $target_pid is still running after force-stop" >&2
  return 1
}

checkAllowMemory() {
  os=`uname`
  totalMemory=$(`echo getTotalMemory`)
  total=`expr $totalMemory / 1024`
  if [[ $os == 'Darwin' ]]; then
    return
  fi

  if [[ $total -lt $ALLOW_MIN_MEMORY ]]; then
    echo "warn: the memory $total MB cannot be smaller than the minimum memory $ALLOW_MIN_MEMORY MB"
    exit
  elif [[ $SPECIFY_MEMORY -gt 0 ]] &&
   [[ $SPECIFY_MEMORY -lt $ALLOW_MIN_MEMORY ]]; then
    echo "warn: the specified memory $SPECIFY_MEMORY MB cannot be smaller than the minimum memory $ALLOW_MIN_MEMORY MB"
    echo 'warn: start abort'
    exit
  fi
}

setTCMalloc() {
  os=`uname`
  if [[ $os == 'Linux' ]] || [[ $os == 'linux' ]] ; then
    lib_tc_malloc="/usr/lib64/libtcmalloc.so"
    if [[ -f $lib_tc_malloc ]]; then
      export LD_PRELOAD="$lib_tc_malloc"
      export TCMALLOC_RELEASE_RATE=10
    else
      echo 'info: recommended for linux systems using tcmalloc as the default memory management tool'
    fi
  fi
}

getTotalMemory() {
  os=`uname`
  if [[ $os == 'Linux' ]] || [[ $os == 'linux' ]] ; then
    total=$(cat /proc/meminfo | grep MemTotal | awk -F ' ' '{print $2}')
    echo $total
    return
  elif [[  $os == 'Darwin' ]]; then
    total=$(sysctl -a | grep mem |grep hw.memsize |awk -F ' ' '{print $2}')
    echo `expr $total / 1024`
  fi
}

setJVMMemory() {
  os=`uname`
  if [[ $os == 'Linux' ]] || [[ $os == 'linux' ]] ; then
    if [[ $SPECIFY_MEMORY >0 ]]; then
      max_direct=$(echo "$SPECIFY_MEMORY/1024*0.1" | bc | awk -F. '{print $1"g"}')
      if [[ "$max_direct" != "g" ]]; then
        MAX_DIRECT_MEMORY=$max_direct
      fi
      JVM_MX=$(echo "$SPECIFY_MEMORY/1024*0.6" | bc | awk -F. '{print $1"g"}')
      JVM_MS=$JVM_MX
    else
      total=$(`echo getTotalMemory`)
      MAX_DIRECT_MEMORY=$(echo "$total/1024/1024*0.1" | bc | awk -F. '{print $1"g"}')
      JVM_MX=$(echo "$total/1024/1024*0.6" | bc | awk -F. '{print $1"g"}')
      JVM_MS=$JVM_MX
    fi

  elif [[ $os == 'Darwin' ]]; then
    MAX_DIRECT_MEMORY='1g'
  fi
}

startService() {
  local jar_path

  echo $(date) >>start.log
  if [[ ! $JAR_NAME =~ '-c' ]]; then
     FULL_START_OPT="$FULL_START_OPT -c $DEFAULT_FULL_NODE_CONFIG"
  fi

  if ! jar_path=$(normalizeJarPath "$JAR_NAME") || [[ ! -f "$jar_path" ]]; then
    echo "warn: jar file $JAR_NAME not exist"
    return 1
  fi

  nohup "$JAVACMD" -Xms$JVM_MS -Xmx$JVM_MX -XX:+UseConcMarkSweepGC -XX:+PrintGCDetails -Xloggc:./gc.log \
    -XX:+PrintGCDateStamps -XX:+CMSParallelRemarkEnabled -XX:ReservedCodeCacheSize=256m -XX:+UseCodeCacheFlushing \
    -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m \
    -XX:MaxDirectMemorySize=$MAX_DIRECT_MEMORY -Dio.netty.allocator.type=pooled \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:NewRatio=2 -jar \
    "$jar_path" $FULL_START_OPT >>start.log 2>&1 &
  pid=$!
  echo "info: start java-tron with pid $pid on $HOSTNAME"
  printf 'info: if you need to stop the service, execute: bash start.sh --stop -j %q\n' "$jar_path"
}

rebuildManifest() {
  if [[ $REBUILD_MANIFEST = false ]]; then
    echo 'info: disable rebuild manifest!'
    return
  fi

  if [[ ! -d $REBUILD_DIR ]]; then
    echo "info: database not exists, skip rebuild manifest"
    return
  fi

  ARCHIVE_JAR='ArchiveManifest.jar'
  if [[ -f $ARCHIVE_JAR ]]; then
    echo 'info: execute rebuild manifest.'
  else
    echo 'info: download the rebuild manifest plugin from the github'
    local latest
    latest=$(getLatestReleaseVersion)
    if [[ -z "$latest" ]]; then
      echo 'info: not getting the latest version for ArchiveManifest.jar' >&2
      return 1
    fi
    if ! installVerifiedReleaseArtifact \
      "$latest" "$ARCHIVE_JAR" "$ARCHIVE_JAR"; then
      echo 'info: failed to download and verify ArchiveManifest.jar' >&2
      return 1
    fi
  fi
  if "$JAVACMD" -jar "$ARCHIVE_JAR" -d "$REBUILD_DIR" \
    -m "$REBUILD_MANIFEST_SIZE" -b "$REBUILD_BATCH_SIZE"; then
    echo 'info: rebuild manifest success'
  else
    echo 'info: rebuild manifest fail, log in logs/archive.log' >&2
    return 1
  fi
}

specifyConfig(){
  echo "info: specify the net: $1"
  local netType=$1
  local configName;
  local configUrl;
  local configPath;
  if [[ "$netType" = 'test' ]]; then
    echo "error: Since Nile Testnet may incorporate features not yet available on the Mainnet," >&2
    echo "build and run the node by following the nile-testnet source-code instructions:" >&2
    echo "https://github.com/tron-nile-testnet/nile-testnet#building-the-source-code" >&2
    exit 1
  elif [[ "$netType" = 'private' ]]; then
    configName=$FULL_NODE_CONFIG_PRIVATE_NET
    configUrl=$FULL_NODE_CONFIG_PRIVATE_NET_URL
  else
    echo "warn: no support config $netType" >&2
    exit 1
  fi

  if [[ ! -d $FULL_NODE_CONFIG_DIR ]]; then
    mkdir -p $FULL_NODE_CONFIG_DIR
  fi

  configPath=$FULL_NODE_CONFIG_DIR/$configName
  if [[ -L $configPath ]] || [[ -e $configPath && ! -f $configPath ]]; then
    echo "info: $netType config path is not a regular file: $configPath" >&2
    exit 1
  fi

  if [[ ! -s $configPath ]]; then
    if ! downloadTo "$configUrl" "$configPath"; then
      echo "info: failed to download $netType config"
      exit 1
    fi
  fi
  DEFAULT_FULL_NODE_CONFIG=$configPath
}

restart() {
  if ! stopService; then
    return 1
  fi
  checkAllowMemory
  if ! rebuildManifest; then
    return 1
  fi
  setTCMalloc
  setJVMMemory
  startService
}

while [ -n "$1" ]; do
  case "$1" in
  -c)
    DEFAULT_FULL_NODE_CONFIG=$2
    shift 2
    ;;
  -d)
    REBUILD_DIR=$2/database
    FULL_START_OPT="$FULL_START_OPT $1 $2"
    shift 2
    ;;
  -j)
    JAR_NAME=$2
    shift 2
    ;;
  -p)
    FULL_START_OPT="$FULL_START_OPT $1 $2"
    shift 2
    ;;
  -w)
    FULL_START_OPT="$FULL_START_OPT $1"
    shift 1
    ;;
  --witness)
    FULL_START_OPT="$FULL_START_OPT $1"
    shift 1
    ;;
  --net)
    specifyConfig $2
    shift 2
    ;;
  -m)
    REBUILD_MANIFEST_SIZE=$2
    shift 2
    ;;
  -n)
    JAR_NAME=$2
    shift 2
    ;;
  -b)
    REBUILD_BATCH_SIZE=$2
    shift 2
    ;;
  -cb)
    CLONE_BUILD=true
    shift 1
    ;;
  --download)
    DOWNLOAD=true
    shift 1
    ;;
  --deploy)
    QUICK_START=true
    shift 1
    ;;
  --release)
    QUICK_START=true
    shift 1
    ;;
  --clone)
    cloneCode
    exit
    ;;
  -mem)
    SPECIFY_MEMORY=$2
    shift 2
    ;;
  --disable-rewrite-manifest|--disable-rewrite-manifes)
    REBUILD_MANIFEST=false
    shift 1
    ;;
  -dr)
    REBUILD_MANIFEST=false
    shift 1
    ;;
  --upgrade)
    UPGRADE=true
    shift 1
    ;;
  --run)
    shift 1
    ;;
  --stop)
    STOP=true
    shift 1
    ;;
  FullNode)
    shift 1
    ;;
  FullNode.jar)
    shift 1
    ;;
  *.jar)
    shift 1
    ;;
  *)
    if [[ $ALL_OPT_LENGTH -eq 1 ]]; then
      if [[ ! "$1" =~ "-" ]] && [[ ! "$1" =~ "--" ]]; then
        if [[ $1 =~ '.jar' ]]; then
          JAR_NAME=$1
        else
          JAR_NAME="$1.jar"
        fi
        restart
        exit
      fi
    fi
    FULL_START_OPT="$FULL_START_OPT $@"
    break
    ;;
  esac
done

if [[ $STOP == true ]]; then
  if ! stopService; then
    exit 1
  fi
  exit 0
fi

if [[ $IS_BACKUP_GC_LOG = true ]]; then
  backupGCLog
fi

if [[ $CLONE_BUILD == true ]];then
  cloneBuild
fi

if [[ $QUICK_START == true ]]; then
  if ! quickStart; then
    exit 1
  fi
fi

if [[ $UPGRADE == true ]]; then
  if ! upgrade; then
    exit 1
  fi
fi

if [[ $DOWNLOAD == true ]]; then
  latest=$(getLatestReleaseVersion)
  if [[ -n $latest ]]; then
    if ! installVerifiedReleaseArtifact \
      "$latest" "$RELEASE_FULL_NODE_ASSET" "$JAR_NAME"; then
      exit 1
    fi
    exit 0
  else
    echo 'info: not getting the latest version' >&2
    exit 1
  fi
fi

if ! restart; then
  exit 1
fi
