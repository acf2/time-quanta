#!/bin/bash

SECONDS_IN_MINUTE=60

QUANTUM_MINUTES=25
INTERRUPTION_MINUTES=5
HUGE_INTERRUPTION_MINUTES=15

ROOT=.quanta
LIST=tasks
LOG=log
STATE=state

NO_ROOT_MSG="Cannot find tq unit"
NO_TASK_MSG="You should specify a task number"
NAN_MSG="Argument should be a number"
NO_SUCH_TASK_MSG="There is no such task"
TOO_FEW_ARGUMENTS_MSG="Too few arguments"

INTERNAL_ERROR_NO_LIST="INTERNAL: No todo list. You might want to re-init tq unit"
INTERNAL_ERROR_NO_LOG="INTERNAL: No log file. You might want to re-init tq unit"
INTERNAL_ERROR_NO_STATE="INTERNAL: No state file. You might want to re-init tq unit"

escape() {
	while read data; do
		echo $data | sed 's/\\/\\\\/gI;s/(/\\(/gI;s/)/\\)/gI;s/\[/\\[/gI;s/\]/\\]/gI;';
	done;
}

init() {
	[ ! -d "$ROOT" ] && (mkdir "$ROOT" && touch "$ROOT/$LIST" "$ROOT/$LOG" "$ROOT/$STATE");
	echo '0' > "$ROOT/$STATE";
}

reset_sequence() {
	[ ! -d "$ROOT" ] && echo $NO_ROOT_MSG && return 1; 
	echo '0' > "$ROOT/$STATE";
}

show_list() {
	[ ! -d "$ROOT" ] && echo $NO_ROOT_MSG && return 1; 
	[ ! -f "$ROOT/$LIST" ] && echo $INTERNAL_ERROR_NO_LIST && return -1; 
	LESS="-XRFN" less "$ROOT/$LIST";
}

show_log() {
	[ ! -d "$ROOT" ] && echo $NO_ROOT_MSG && return 1; 
	[ ! -f "$ROOT/$LOG" ] && echo $INTERNAL_ERROR_NO_LOG && return -2; 
	LESS="-PProgress$ -XRFn" less "$ROOT/$LOG";
}

add_task() {
	[ ! -d "$ROOT" ] && echo $NO_ROOT_MSG && return 1; 
	echo "$@" >> "$ROOT/$LIST";
}

remove_task() {
	[ ! -d "$ROOT" ] && echo $NO_ROOT_MSG && return 1; 
	[ ! -f "$ROOT/$LIST" ] && echo $INTERNAL_ERROR_NO_LIST && return -1; 

	[ "$1" = 'all' ] && echo -n >"$ROOT/$LIST" || {
		lst="";
		for i in $@; do
			[[ "$i" =~ ^[0-9]+$ ]] && lst+=" $i";
		done
		sed -i "$(echo "$lst" | sed -E 's/ *([0-9]+)/\1d;/gI')" "$ROOT/$LIST";
	}
}

# INTERNAL: No checks
add_mark() {
	TASK=$(sed $1'!d' "$ROOT/$LIST" | escape | tr -d '\n');
	STR_TASK=$(sed $1'!d' "$ROOT/$LIST" | tr -d '\n'); # Crutches everywhere!

	# If no such task in log, create it.
	grep -q -E "^$TASK: " "$ROOT/$LOG" || echo "$STR_TASK: " >> "$ROOT/$LOG";

	grep -q -E "^$TASK: [| ]*\|\|\|\|$" "$ROOT/$LOG" &&
	sed -i -E "s/^($TASK: [| ]*)$/\1 |/" "$ROOT/$LOG" || # previous chunk is complete
	sed -i -E "s/^($TASK: [| ]*)$/\1|/" "$ROOT/$LOG"; # previous chunk is incomplete
}

quantum() {
	[ ! -d "$ROOT" ] && echo $NO_ROOT_MSG && return 1; 
	[ $# -lt 1 ] && echo $NO_TASK_MSG && return 2;
	[[ ! "$1" =~ ^[0-9]+$ ]] && echo $NAN_MSG && return 3;

	[ ! -f "$ROOT/$LIST" ] && echo $INTERNAL_ERROR_NO_LIST && return -1; 
	TASK=$(sed $1'!d' "$ROOT/$LIST" | escape | tr -d '\n');
	[ -z "$TASK" ] && echo $NO_SUCH_TASK_MSG && return 4;

	[ ! -f "$ROOT/$STATE" ] && echo $INTERNAL_ERROR_NO_STATE && return -3; 
	CURRENT_STATE=$( cat "$ROOT/$STATE" );

	HEADER="TQ-$(( $CURRENT_STATE + 1 ))";
	PREMESSAGE="Time quantum $(( $CURRENT_STATE + 1 )) ($(( $CURRENT_STATE % 4 + 1)))\n\tTask: $TASK";
	AFTERMARKS=$(printf "%$(( $CURRENT_STATE % 4 + 1 ))s" | tr " " "|");

	if [ $(( $CURRENT_STATE % 4 )) -eq 3 ]; then
		AFTERMESSAGE="Huge interlude:\n\t15 minutes\n\tmarks: $AFTERMARKS";
		WAIT_MINUTES=$HUGE_INTERRUPTION_MINUTES;
	else
		AFTERMESSAGE="Interruption:\n\t5 minutes\n\tmarks: $AFTERMARKS";
		WAIT_MINUTES=$INTERRUPTION_MINUTES;
	fi

	ENDMESSAGE="Break had ended";

	notify-send --urgency=low "$HEADER" "$PREMESSAGE\n\tTimepoint: $(date +'%H%M')" &&
	sleep $(( $QUANTUM_MINUTES * $SECONDS_IN_MINUTE )) &&
	add_mark $1 && 
	echo "$(( $CURRENT_STATE + 1 ))" >"$ROOT/$STATE" &&
	notify-send --urgency=low "$HEADER" "$AFTERMESSAGE\n\tTimepoint: $(date +'%H%M')" &&
	sleep $(( $WAIT_MINUTES * $SECONDS_IN_MINUTE )) &&
	notify-send --urgency=low "$HEADER" "$ENDMESSAGE\n\tTimepoint: $(date +'%H%M')";
}

USAGE_MSG="Usage: tq <command> [<args>]"

main() {
	[ $# -lt 1 ] && echo $TOO_FEW_ARGUMENTS_MSG && echo -e "$USAGE_MSG\n\t'tq help' will show help" && return 0;

	COMMAND="$1"
	ARGUMENTS="${@:2}"

	HELP_MSG=$(cat <<EOF
$USAGE_MSG

Commands:
	help                                                      show this help
	init                                                      initilaize tq unit
	{st[art] | r[eset]}                                       reset quantum counter (useful in the beginning of a day)
	t[asks]                                                   show all available tasks (and their indicies)
	pr[ogress]                                                show progress for all tasks (even done ones)
	add <task heading>                                        add new task
	{done | rm | remove} <index> [<index> [<index> [...]]]    remove one or many tasks
	{do | quantum-for | qf} <index>                           start time quantum for particular task
EOF
)

	case "$COMMAND" in
		"init")
			init $ARGUMENTS; ;;
		"st"|"start"|"r"|"reset")
			reset_sequence $ARGUMENTS;
			;;
		"t"|"tasks")
			show_list $ARGUMENTS;
			;;
		"pr"|"progress")
			show_log $ARGUMENTS;
			;;
		"add")
			add_task $ARGUMENTS;
			;;
		"done"|"rm"|"remove")
			remove_task $ARGUMENTS;
			;;
		"do"|"qf"|"quantum-for")
			quantum $ARGUMENTS;
			;;
		"help")
			echo -e "$HELP_MSG";
			;;
		*)
			echo "Unknown command: $COMMAND";
			;;
	esac
}

main "$@";
