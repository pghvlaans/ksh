########################################################################
#                                                                      #
#               This software is part of the ast package               #
#          Copyright (c) 1982-2012 AT&T Intellectual Property          #
#          Copyright (c) 2020-2023 Contributors to ksh 93u+m           #
#                      and is licensed under the                       #
#                 Eclipse Public License, Version 2.0                  #
#                                                                      #
#                A copy of the License is available at                 #
#      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      #
#         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         #
#                                                                      #
#                  David Korn <dgk@research.att.com>                   #
#                  Martijn Dekker <martijn@inlv.org>                   #
#            Johnothan King <johnothanking@protonmail.com>             #
#                Govind Kamat <govind_kamat@yahoo.com>                 #
#               K. Eugene Carlson <kvngncrlsn@gmail.com>               #
#                      Phi <phi.debian@gmail.com>                      #
#                                                                      #
########################################################################

. "${SHTESTS_COMMON:-${0%/*}/_common}"

# These are tests for the interactive shell, run in a pseudoterminal utility
# called 'pty', which allows for scripting interactive sessions and which is
# installed in arch/*/bin while building. To understand these tests, first
# read the pty manual by running: arch/*/bin/pty --man
#
# Do not globally set the locale; these tests must pass for all locales.

# the trickiest part of the tests is avoiding typeahead
# in the pty dialogue

((!SHOPT_SCRIPTONLY)) || { warning "interactive shell was compiled out -- tests skipped"; exit 0; }
whence -q pty || { warning "pty command not found -- tests skipped"; exit 0; }
case $(uname -s) in
Darwin | DragonFly | FreeBSD | Linux | MidnightBSD )
	;;
* )	warning "pty not confirmed to work correctly on this system -- tests skipped"
	exit 0 ;;
esac

# On some systems, the stty command does not appear to work correctly on a pty pseudoterminal.
# To avoid false regressions, we have to set 'erase' and 'kill' on the real terminal.
if	test -t 0 2>/dev/null </dev/tty && stty_restore=$(stty -g </dev/tty)
then	trap 'stty "$stty_restore" </dev/tty' EXIT  # note: on ksh, the EXIT trap is also triggered for termination due to a signal
	stty erase ^H kill ^X </dev/tty >/dev/tty 2>&1
else	warning "cannot set tty state -- tests skipped"
	exit 0
fi

bintrue=$(whence -p true)

x=$( "$SHELL" 2>&1 <<- \EOF
		trap 'exit 0' EXIT
		bintrue=$(whence -p true)
		set -o monitor
		{
			eval $'command set -o vi 2>/dev/null\npty $bintrue'
		} < /dev/null & pid=$!
		jobs
		kill $$
	EOF
)
[[ $x == *Stop* ]] && err_exit "monitor mode enabled incorrectly causes job to stop (got $(printf %q "$x"))"

if	[[ -o xtrace ]]
then	debug=--debug=1
else	debug=
fi

function tst
{
	integer lineno=$1 offset
	typeset text

	pty $debug --dialogue --messages='/dev/fd/1' 2>/dev/tty $SHELL |
	while	read -r text
	do	if	[[ $text == *debug* ]]
		then	print -u2 -r -- "$text"
		else	offset=${text/*: line +([[:digit:]]):*/\1}
			err\_exit "$lineno" "${text/: line $offset:/: line $(( lineno + offset)):}"
		fi
	done
}

# VISUAL, or if that is not set, EDITOR, automatically sets vi, gmacs or emacs mode if
# its value matches *[Vv][Ii]*, *gmacs* or *macs*, respectively. See put_ed() in init.c.
unset EDITOR
if	((SHOPT_VSH))
then	export VISUAL=vi
elif	((SHOPT_ESH))
then	export VISUAL=emacs
else	unset VISUAL
fi
export PS1=':test-!: ' PS2='> ' PS4=': ' ENV=/./dev/null EXINIT= HISTFILE= TERM=dumb

if	! pty $bintrue < /dev/null
then	warning "pty command hangs on $bintrue -- tests skipped"
	exit 0
fi

# ksh invokes tput(1) to get terminal escape sequences necessary for multiline editing.
# If tput is not available, tests requiring multiline editing would fail.
typeset -si multiline
command -pv tput >/dev/null
if	! let "multiline = ! $?"
then	warning "tput(1) not available on default path; tests that require multiline editing are skipped"
fi

tst $LINENO <<"!"
L POSIX sh 026(C)

# If the User Portability Utilities Option is supported:  When the
# POSIX locale is specified and a background job is suspended by a
# SIGTSTP signal then the <state> field in the output message is set to
# Stopped, Suspended, Stopped(SIGTSTP) or Suspended(SIGTSTP).

d 15
I ^\r?\n$
p :test-1:
w sleep 60 &
u [[:digit:]]\r?\n$
s 100
p :test-2:
w kill -TSTP $!
u (Stopped|Suspended)
p :test-3:
w kill -KILL $!
w wait
u (Killed|Done)
!

tst $LINENO <<"!"
L POSIX sh 028(C)

# If the User Portability Utilities Option is supported:  When the
# POSIX locale is specified and a background job is suspended by a
# SIGTTIN signal then the <state> field in the output message is set to
# Stopped(SIGTTIN) or Suspended(SIGTTIN).

d 15
I ^\r?\n$
p :test-1:
w sleep 60 &
u [[:digit:]]\r?\n$
s 100
p :test-2:
w kill -TTIN $!
u (Stopped|Suspended) \(SIGTTIN\)
p :test-3:
w kill -KILL $!
w wait
u (Killed|Done)
!

tst $LINENO <<"!"
L POSIX sh 029(C)

# If the User Portability Utilities Option is supported:  When the
# POSIX locale is specified and a background job is suspended by a
# SIGTTOU signal then the <state> field in the output message is set to
# Stopped(SIGTTOU) or Suspended(SIGTTOU).

d 15
I ^\r?\n$
p :test-1:
w sleep 60 &
u [[:digit:]]\r?\n$
s 100
p :test-2:
w kill -TTOU $!
u (Stopped|Suspended) \(SIGTTOU\)
p :test-3:
w kill -KILL $!
w wait
u (Killed|Done)
!

tst $LINENO <<"!"
L POSIX sh 091(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode an entered
# character other than <newline>, erase, interrupt, kill, control-V,
# control-W, backslash \ (followed by erase or kill), end-of-file and
# <ESC> is inserted in the current command line.

d 15
c echo h
c ell
w o
u ^hello\r?\n$
!

((SHOPT_VSH)) && tst $LINENO <<"!"
L POSIX sh 093(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  After termination of a previous
# command, sh is entered in insert mode.

d 15
w echo hello\E
u ^hello\r?\n$
c echo goo
c dby
w e
u ^goodbye\r?\n$
!

((SHOPT_VSH)) && tst $LINENO <<"!"
L POSIX sh 094(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode an <ESC>
# switches sh into command mode.

d 15
c echo he\E
s 400
w allo
u ^hello\r?\n$
!

if	[[ $(id -u) == 0 ]]
then	warning "running as root: skipping test POSIX sh 096(C)"
else
tst $LINENO <<"!"
L POSIX sh 096(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in command mode the
# interrupt character causes sh to terminate command line editing on
# the current command line, re-issue the prompt on the next line of the
# terminal and to reset the command history so that the command that
# was interrupted is not entered in the history.

d 15
I ^\r?\n$
p :test-1:
w echo first
p :test-2:
w stty intr ^C
p :test-3:
c echo bad\E
s 400
c \cC
w echo scrambled
p :test-4:
w history
u echo first
r stty intr \^C
r echo
r history
!
fi

tst $LINENO <<"!"
L POSIX sh 097(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode a <newline>
# causes the current command line to be executed.

d 15
c echo ok\n
u ^ok\r?\n$
!

if	[[ $(id -u) == 0 ]]
then	warning "running as root: skipping test POSIX sh 099(C)"
else
tst $LINENO <<"!"
L POSIX sh 099(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode the interrupt
# character causes sh to terminate command line editing on the current
# command line, re-issue the prompt on the next line of the terminal
# and to reset the command history so that the command that was
# interrupted is not entered in the history.

d 15
I ^\r?\n$
p :test-1:
w echo first
u ^first
p :test-2:
w stty intr ^C
r
p :test-3:
c echo bad\cC
w echo last
p :test-4:
w history
u echo first
r stty intr \^C
r echo last
r history
!
fi

tst $LINENO <<"!"
L POSIX sh 100(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode the kill
# character clears all the characters from the input line.

d 15
p :test-1:
w stty kill ^X
p :test-2:
c echo bad\cX
w echo ok
u ^ok\r?\n$
!

((SHOPT_VSH || SHOPT_ESH)) && tst $LINENO <<"!"
L POSIX sh 101(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode a control-V
# causes the next character to be inserted even in the case that the
# character is a special insert mode character.
# Testing Requirements: The assertion must be tested with at least the
# following set of characters: <newline>, erase, interrupt, kill,
# control-V, control-W, end-of-file, backslash \ (followed by erase or
# kill) and <ESC>.

d 15
p :test-1:
w stty erase ^H intr ^C kill ^X
p :test-2:
w echo erase=:\cV\cH:
u ^erase=:\r?\n$
p :test-3:
w echo kill=:\cV\cX:
u ^kill=:\cX:\r?\n$
p :test-4:
w echo control-V=:\cV\cV:
u ^control-V=:\cV:\r?\n$
p :test-5:
w echo control-W:\cV\cW:
u ^control-W:\cW:\r?\n$
p :test-6:
w echo EOF=:\cV\cD:
u ^EOF=:\004:\r?\n$
p :test-7:
w echo backslash-erase=:\\\cH:
u ^backslash-erase=:\r?\n$
p :test-8:
w echo backslash-kill=:\\\cX:
u ^backslash-kill=:\cX:\r?\n$
p :test-9:
w echo ESC=:\cV\E:
u ^ESC=:\E:\r?\n$
p :test-10:
w echo interrupt=:\cV\cC:
u ^interrupt=:\cC:\r?\n$
!

tst $LINENO <<"!"
L POSIX sh 104(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in insert mode an
# end-of-file at the beginning of an input line is interpreted as the
# end of input.

d 15
p :test-1:
w trap 'echo done >&2' EXIT
p :test-2:
s 100
c \cD
u ^done\r?\n$
!

if	[[ $(id -u) == 0 ]]
then	warning "running as root: skipping test POSIX sh 111(C)"
else
((SHOPT_VSH)) && tst $LINENO <<"!"
L POSIX sh 111(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in command mode, # inserts
# the character # at the beginning of the command line and causes the
# line to be treated as a comment and the line is entered in the
# command history.

d 15
p :test-1:
c echo save\E
s 400
c #
p :test-2:
w history
u #echo save
r history
!
fi

if	[[ $(id -u) == 0 ]]
then	warning "running as root: skipping test POSIX sh 251(C)"
else
((SHOPT_VSH)) && tst $LINENO <<"!"
L POSIX sh 251(C)

# If the User Portability Utilities Option is supported and shell
# command line editing is supported:  When in command mode, then the
# command N repeats the most recent / or ? command, reversing the
# direction of the search.

d 15
p :test-1:
w echo repeat-1
u ^repeat-1\r?\n$
p :test-2:
w echo repeat-2
u ^repeat-2\r?\n$
p :test-3:
s 100
c \E
s 400
w /rep
u echo repeat-2
c n
r echo repeat-1
c N
r echo repeat-2
w dd
p :test-3:
w echo repeat-3
u ^repeat-3\r?\n$
p :test-4:
s 100
c \E
s 400
w ?rep
r echo repeat-2
c N
r echo repeat-1
c n
r echo repeat-2
c n
r echo repeat-3
!
fi

# This test freezes the 'less' pager on OpenBSD, which is not a ksh bug.
: <<\disabled
whence -q less &&
TERM=vt100 tst $LINENO <<"!"
L process/terminal group exercise

d 15
w m=yes; while true; do echo $m-$m; done | less
u :$|:\E|lines
c \cZ
r Stopped
w fg
u yes-yes
!
disabled

# Test file name completion in vi mode
if((SHOPT_VSH)); then
mkdir "/tmp/fakehome_$$" && tst $LINENO <<!
L vi mode file name completion

# Completing a file name in vi mode that contains '~' and has a
# base name the same length as the home directory's parent directory
# shouldn't fail.

d 15
w set -o vi; HOME=/tmp/fakehome_$$; touch ~/testfile_$$
w echo ~/tes\t
u ^/tmp/fakehome_$$/testfile_$$\r?\n$
!
rm -r "/tmp/fakehome_$$"
fi # SHOPT_VSH

VISUAL='' tst $LINENO <<"!"
L raw Bourne mode literal tab characters

# With wide characters (e.g. UTF-8) disabled, raw mode is handled by ed_read()
# in edit.c; it does not expand tab characters on the command line.
# With wide characters enabled, and if vi mode is compiled in, raw mode is
# handled by ed_viread() in vi.c (even though vi mode is off); it expands tab
# characters to spaces on the command line. See slowread() in io.c.

d 15
p :test-1:
w set +o emacs 2>/dev/null
p :test-2:
w true /de\tv/nu\tl\tl
r ^:test-2: true (/de\tv/nu\tl\tl|/de       v/nu    l       l)\r\n$
p :test-3:
!

VISUAL='' tst $LINENO <<"!"
L raw Bourne mode backslash handling

# The escaping backslash feature should be disabled in the raw Bourne mode.
# This is tested with both erase and kill characters.

d 15
p :test-1:
w set +o emacs 2>/dev/null
p :test-2:
w stty erase ^H kill ^X
p :test-3:
w true string\\\\\cH\cH
r ^:test-3: true string\r\n$
p :test-4:
w true incorrect\\\cXtrue correct
r ^:test-4: true correct\r\n$
!

set --
((SHOPT_VSH)) && set -- "$@" vi
((SHOPT_ESH)) && set -- "$@" emacs gmacs
for mode do
VISUAL=$mode tst $LINENO << !
L escaping backslashes in $mode mode

# Backslashes should only be escaped if the previous input was a backslash.
# Other backslashes stored in the input buffer should be erased normally.

d 40
p :test-1:
w stty erase ^H
p :test-2:
w true string\\\\\\\\\\cH\\cH\\cH
r ^:test-2: true string\\r\\n$
!
done

tst $LINENO <<"!"
L notify job state changes

# 'set -b' should immediately notify the user about job state changes.

p :test-1:
w set -b; sleep .01 &
u Done
!

# Tests for 'test -t'. These were moved here from bracket.sh because they require a tty.
cat >test_t.sh <<"EOF"
integer n
redirect {n}< /dev/tty
[[ -t $n ]] && echo OK0 || echo "[[ -t n ]] fails when n > 9"
# _____ Verify that [ -t 1 ] behaves sensibly inside a command substitution.
#	This is the simple case that doesn't do any redirection of stdout within
#	the command substitution. Thus the [ -t 1 ] test should be false.
expect=$'begin\nend'
actual=$(echo begin; [ -t 1 ] || test -t 1 || [[ -t 1 ]] && echo -t 1 is true; echo end)
[[ $actual == "$expect" ]] && echo OK1 || echo 'test -t 1 in comsub fails' \
	"(expected $(printf %q "$expect"), got $(printf %q "$actual"))"
actual=$(echo begin; [ -n X -a -t 1 ] || test -n X -a -t 1 || [[ -n X && -t 1 ]] && echo -t 1 is true; echo end)
[[ $actual == "$expect" ]] && echo OK2 || echo 'test -t 1 in comsub fails (compound expression)' \
	"(expected $(printf %q "$expect"), got $(printf %q "$actual"))"
# Same for the ancient compatibility hack for 'test -t' with no arguments.
actual=$(echo begin; [ -t ] || test -t && echo -t is true; echo end)
[[ $actual == "$expect" ]] && echo OK3 || echo 'test -t in comsub fails' \
	"(expected $(printf %q "$expect"), got $(printf %q "$actual"))"
actual=$(echo begin; [ -n X -a -t ] || test -n X -a -t && echo -t is true; echo end)
[[ $actual == "$expect" ]] && echo OK4 || echo 'test -t in comsub fails (compound expression)' \
	"(expected $(printf %q "$expect"), got $(printf %q "$actual"))"
#	This is the more complex case that does redirect stdout within the command
#	substitution to the actual tty. Thus the [ -t 1 ] test should be true.
actual=$(echo begin; exec >/dev/tty; [ -t 1 ] && test -t 1 && [[ -t 1 ]]) \
&& echo OK5 || echo 'test -t 1 in comsub with exec >/dev/tty fails'
actual=$(echo begin; exec >/dev/tty; [ -n X -a -t 1 ] && test -n X -a -t 1 && [[ -n X && -t 1 ]]) \
&& echo OK6 || echo 'test -t 1 in comsub with exec >/dev/tty fails (compound expression)'
# Same for the ancient compatibility hack for 'test -t' with no arguments.
actual=$(echo begin; exec >/dev/tty; [ -t ] && test -t) \
&& echo OK7 || echo 'test -t in comsub with exec >/dev/tty fails'
actual=$(echo begin; exec >/dev/tty; [ -n X -a -t ] && test -n X -a -t) \
&& echo OK8 || echo 'test -t in comsub with exec >/dev/tty fails (compound expression)'
# The broken ksh2020 fix for [ -t 1 ] (https://github.com/att/ast/pull/1083) caused
# [ -t 1 ] to fail in non-comsub virtual subshells.
( test -t 1 ) && echo OK9 || echo 'test -t 1 in virtual subshell fails'
( test -t ) && echo OK10 || echo 'test -t in virtual subshell fails'
got=$(test -t 1 >/dev/tty && echo ok) && [[ $got == ok ]] && echo OK11 || echo 'test -t 1 in comsub fails'
EOF
tst $LINENO <<"!"
L test -t 1 inside command substitution
d 40
p :test-1:
w . ./test_t.sh
r ^:test-1: \. \./test_t\.sh\r\n$
r ^OK0\r\n$
r ^OK1\r\n$
r ^OK2\r\n$
r ^OK3\r\n$
r ^OK4\r\n$
r ^OK5\r\n$
r ^OK6\r\n$
r ^OK7\r\n$
r ^OK8\r\n$
r ^OK9\r\n$
r ^OK10\r\n$
r ^OK11\r\n$
r ^:test-2:
!

tst $LINENO <<"!"
L race condition while launching external commands

# Test for bug in ksh binaries that use posix_spawn() while job control is active.
# See discussion at: https://github.com/ksh93/ksh/issues/79

d 40
p :test-1:
w printf '%s\\n' 1 2 3 4 5 | while read; do ls /dev/null; done
r ^:test-1: printf '%s\\n' 1 2 3 4 5 | while read; do ls /dev/null; done\r\n$
r ^/dev/null\r\n$
r ^/dev/null\r\n$
r ^/dev/null\r\n$
r ^/dev/null\r\n$
r ^/dev/null\r\n$
r ^:test-2:
!

((SHOPT_ESH)) && [[ -o ?backslashctrl ]] && tst $LINENO <<"!"
L nobackslashctrl in emacs

d 15
p :test-1:
w set -o emacs --nobackslashctrl

# --nobackslashctrl shouldn't be ignored by reverse search
p :test-2:
w \cR\\\cH\cH
r ^:test-2: \r\n$
!

((SHOPT_ESH)) && tst $LINENO <<"!"
L emacs backslash escaping

d 40
p :test-1:
w set -o emacs

# Test for too many backslash deletions in reverse-search mode
p :test-2:
w \cRset\\\\\\\\\cH\cH\cH\cH\cH
r ^:test-2: set -o emacs$
!

((SHOPT_ESH)) && tst $LINENO <<"!"
L emacs interrupt character

d 40
p :test-1:
w set -o emacs

# \ should escape the interrupt character (usually Ctrl+C)
p :test-2:
w true \\\cC
r ^:test-2: true \^C
!

((SHOPT_VSH)) && touch vi_completion_A_file vi_completion_B_file && tst $LINENO <<"!"
L vi filename completion menu

d 15
c ls vi_co\t\t
r ls vi_completion\r\n$
r ^1) vi_completion_A_file\r\n$
r ^2) vi_completion_B_file\r\n$
w 2\t
r ^:test-1: ls vi_completion_B_file \r\n$
r ^vi_completion_B_file\r\n$

# 93v- bug: tab completion writes past input buffer
# https://github.com/ksh93/ksh/issues/195

# ...reproducer 1
c ls vi_compl\t\t
r ls vi_completion\r\n$
r ^1) vi_completion_A_file\r\n$
r ^2) vi_completion_B_file\r\n$
w aB_file
r ^:test-2: ls vi_completion_B_file\r\n$
r ^vi_completion_B_file\r\n$

# ...reproducer 2
c \rls vi_comple\t\t
u ls vi_completion\r\n$
r ^1) vi_completion_A_file\r\n$
r ^2) vi_completion_B_file\r\n$
w 0$aA_file
r ^:test-3: ls vi_completion_A_file\r\n$
r ^vi_completion_A_file\r\n$
!

tst $LINENO <<"!"
L syntax error added to history file

# https://github.com/ksh93/ksh/issues/209

d 40
p :test-1:
w do something
r ^:test-1: do something\r\n$
r : syntax error: `do' unexpected\r\n$
w fc -lN1
r ^:test-2: fc -lN1\r\n$
r \tdo something\r\n$
!

tst $LINENO <<"!"
L value of $? after the shell uses a variable with a discipline function

d 15
w PS1.get() { true; }; PS2.get() { true; }; false
u PS1.get\(\) \{ true; \}; PS2.get\(\) \{ true; \}; false
w echo "Exit status is: $?"
u Exit status is: 1
w LINES.set() { return 13; }
u LINES.set\(\) \{ return 13; \}
w echo "Exit status is: $?"
u Exit status is: 0

# It's worth noting that the test below will always fail in ksh93u+ and ksh2020,
# even when $PS2 lacks a discipline function (see https://github.com/ksh93/ksh/issues/117).
# After that bug was fixed the test below could still fail if PS2.get() existed.
w false
w (
w exit
w )
w echo "Exit status is: $?"
u Exit status is: 1
!

((SHOPT_ESH)) && ((SHOPT_VSH)) && tst $LINENO <<"!"
L crash after switching from emacs to vi mode

# In ksh93r using the vi 'r' command after switching from emacs mode could
# trigger a memory fault: https://bugzilla.opensuse.org/show_bug.cgi?id=179917

d 40
p :test-1:
w exec "$SHELL" -o emacs
r ^:test-1: exec "\$SHELL" -o emacs\r\n$
p :test-1:
w set -o vi
r ^:test-1: set -o vi\r\n$
p :test-2:
c \Erri
w echo Success
r ^:test-2: echo Success\r\n$
r ^Success\r\n$
!

((SHOPT_VSH || SHOPT_ESH)) && tst $LINENO <<"!"
L value of $? after tilde expansion in tab completion

# Make sure that a .sh.tilde.set discipline function
# cannot influence the exit status.

d 15
w .sh.tilde.set() { true; }
w HOME=/tmp
w false ~\t
u false /tmp
w echo "Exit status is: $?"
u Exit status is: 1
w (exit 42)
w echo $? ~\t
u 42 /tmp
!

((SHOPT_MULTIBYTE && (SHOPT_VSH || SHOPT_ESH))) &&
[[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]] &&
touch $'XXX\xc3\xa1' $'XXX\xc3\xab' &&
tst $LINENO <<"!"
L autocomplete should not fill partial multibyte characters
# https://github.com/ksh93/ksh/issues/223

d 40
p :test-1:
w : XX\t
r ^:test-1: : XXX\r\n$
!

((SHOPT_VSH)) && tst $LINENO <<"!"
L Using b, B, w and W commands in vi mode
# https://github.com/att/ast/issues/1467

d 40
p :test-1:
w set -o vi
r ^:test-1: set -o vi\r\n$
w echo asdf\EbwBWa
r ^:test-2: echo asdf\r\n$
r ^asdf\r\n$
!

((SHOPT_ESH)) && mkdir -p emacstest/123abc && VISUAL=emacs tst $LINENO <<"!"
L autocomplete stops numeric input
# https://github.com/ksh93/ksh/issues/198

d 15
p :test-1:
w cd emacste\t123abc
r ^:test-1: cd emacstest/123abc\r\n$
!

echo '((' >$tmp/synerror
ENV=$tmp/synerror tst $LINENO <<"!"
L syntax error in profile causes exit on startup
# https://github.com/ksh93/ksh/issues/281

d 40
r /synerror: syntax error: `\(' unmatched\r\n$
p :test-1:
w echo ok
r ^:test-1: echo ok\r\n$
r ^ok\r\n$
!

((SHOPT_VSH)) && tst $LINENO <<"!"
L split on quoted whitespace when extracting words from command history
# https://github.com/ksh93/ksh/pull/291

d 40
p :test-1:
w true ls One\\ "Two Three"$'Four Five'.mp3
r ^:test-1: true ls One\\ "Two Three"\$'Four Five'\.mp3\r\n$
p :test-2:
w :\E_
r ^:test-2: : One\\ "Two Three"\$'Four Five'\.mp3\r\n$
!

# needs non-dumb terminal for multiline editing
((multiline && SHOPT_VSH)) && TERM=vt100 tst $LINENO <<"!"
L crash when entering comment into history file (vi mode)
# https://github.com/att/ast/issues/798

d 40
p :test-1:
c foo \E#
r ^:test-1: #foo\r\n$
w hist -lnN 1
r ^:test-2: hist -lnN 1\r\n$
r \t#foo\r\n$
r \thist -lnN 1\r\n$
!

((SHOPT_VSH || SHOPT_ESH)) && tst $LINENO <<"!"
L tab completion while expanding ${.sh.*} variables
# https://github.com/att/ast/issues/1461
# also tests $'...' string: https://github.com/ksh93/ksh/issues/462

d 40
p :test-1:
w test \$'foo\\'bar' \$\{.sh.level\t
r ^:test-1: test \$'foo\\'bar' \$\{.sh.level\}\r\n$
!

((SHOPT_VSH || SHOPT_ESH)) && tst $LINENO <<"!"
L tab completion executes command substitutions
# https://github.com/ksh93/ksh/issues/268
# https://github.com/ksh93/ksh/issues/462#issuecomment-1038482307

d 40
p :test-1:
w $(echo true)\t
r ^:test-1: \$\(echo true\)\r\n$
p :test-2:
w `echo true`\t
r ^:test-2: `echo true`\r\n$
p :test-3:
w '`/dev\t
r ^:test-3: '`/dev[[:blank:]]*\r\n$
# escape from PS2 prompt with Ctrl+C
r ^> $
c \cC
p :test-4:
w '$(/dev\t
r ^:test-4: '\$\(/dev[[:blank:]]*\r\n$
r ^> $
c \cC
p :test-5:
w $'`/dev\t
r ^:test-5: \$'`/dev[[:blank:]]*\r\n$
!

# needs non-dumb terminal for multiline editing
((multiline && SHOPT_ESH)) && VISUAL=emacs TERM=vt100 tst $LINENO <<"!"
L emacs: keys with repeat parameters repeat extra steps
# https://github.com/ksh93/ksh/issues/292

d 15
p :test-1:
w : foo bar delete add\1\6\6\E3\Ed
r ^:test-1: :  add\r\n$
p :test-2:
w : foo bar delete add\E3\Eh
r ^:test-2: : foo \r\n$
p :test-3:
w : test_string\1\6\6\E3\E[3~
r ^:test-3: : t_string\r\n$
p :test-4:
w : test_string\1\E6\E[C\4
r ^:test-4: : teststring\r\n$
!

tst $LINENO <<"!"
L crash with KEYBD trap after entering multi-line command substitution
# https://www.mail-archive.com/ast-users@lists.research.att.com/msg00313.html

d 15
p :test-1:
w trap : KEYBD
w : $(
w true); echo "Exit status is $?"
u Exit status is 0
!

tst $LINENO <<"!"
L interrupted PS2 discipline function
# https://github.com/ksh93/ksh/issues/347

d 40
p :test-1:
w PS2.get() { trap --bad-option 2>/dev/null; .sh.value="NOT REACHED"; }
p :test-2:
w echo \$\(
r :test-2: echo \$\(
w echo one \\
r > echo one \\
w two three
r > two three
w echo end
r > echo end
w \)
r > \)
r one two three end
!

((SHOPT_VSH || SHOPT_ESH)) && tst $LINENO <<"!"
L tab completion of '.' and '..'
# https://github.com/ksh93/ksh/issues/372

d 40

# typing '.' followed by two tabs should show a menu that includes "number) ../"
p :test-1:
w : .\t\t
u ) \.\./\r\n$

# typing '..' followed by a tab should complete to '../' (as it is
# known that there are no files starting with '..' in the test PWD)
p :test-2:
w : ..\t
r : \.\./\r\n$
!

tst $LINENO <<"!"
L Ctrl+C with SIGINT ignored
# https://github.com/ksh93/ksh/issues/343

d 40

# SIGINT ignored by child
p :test-1:
w PS1=':child-!: ' "$SHELL"
p :child-1:
w trap '' INT
p :child-2:
c \\\cC
r :child-2:
w echo "OK $PS1"
u ^OK :child-!: \r\n$
w exit

# SIGINT ignored by parent
p :test-2:
w (trap '' INT; ENV=/./dev/null PS1=':child-!: ' "$SHELL")
p :child-1:
c \\\cC
r :child-1:
w echo "OK $PS1"
u ^OK :child-!: \r\n$
w exit

# SIGINT ignored by parent, trapped in child
p :test-3:
w (trap '' INT; ENV=/./dev/null PS1=':child-!: ' "$SHELL")
p :child-1:
w trap 'echo test' INT
p :child-2:
c \\\cC
r :child-2:
w echo "OK $PS1"
u ^OK :child-!: \r\n$
w exit
!

touch "$tmp/foo bar"
# needs non-dumb terminal for multiline editing
((multiline && (SHOPT_VSH || SHOPT_ESH))) && TERM=vt100 tst $LINENO <<!
L tab completion with space in string and -o noglob on
# https://github.com/ksh93/ksh/pull/413
# Amended to test that completion keeps working after -o noglob

d 40
p :test-1:
w set -o noglob
p :test-2:
w echo $tmp/foo\\\\ \\t
r ^:test-2: echo $tmp/foo\\\\ bar \\r\\n$
r ^$tmp/foo bar\\r\\n$
!

((SHOPT_HISTEXPAND)) && HISTFILE=$tmp/tmp_histfile tst $LINENO <<!
L history expansion of an out-of-range event

d 40
p :test-1:
w set -H
p :test-2:
w echo "!99"
r !99
r : !99: event not found\r\n$
!

mkfifo testfifo
tst $LINENO <<"!"
L suspend a blocked write to a FIFO
# https://github.com/ksh93/ksh/issues/464

d 40
p :test-1:
w echo >testfifo
r echo
# untrapped SIGTSTP (Ctrl+Z) should be ineffective here and just print ^Z
c \cZ
r ^\^Z$
# Ctrl+C should interrupt it and trigger an error message
c \cC
r ^\^C.*: testfifo: cannot create \[.*\]\r\n$
p :test-2:
w echo ok
r echo
r ^ok\r\n$
!

# TODO: fails too often on github runners; 'set -b' must still
# have a race condition when several jobs terminate all at once
: <<\DISABLED
tst $LINENO <<"!"
L --notify does not report all simultaneously terminated jobs

d 15
p :test-1:
w set -b; sleep .1 & sleep .1 & sleep .1 &
u Done
u Done
u Done
!
DISABLED

((SHOPT_HISTEXPAND)) && HISTFILE=$tmp/tmp_histfile tst $LINENO <<"!"
L history expansion: history comment character stops line from being processed
# https://github.com/ksh93/ksh/issues/513

d 15
p :test-1:
w set -H
p :test-2:
w true ${#v} !non_existent
u : !non_existent: event not found
w histchars='!^@'
p :test-3:
w true \\@ !non_existent
u : !non_existent: event not found
p :test-4:
w echo @ !non_existent
u @ !non_existent\r\n$
!

((SHOPT_VSH)) && tst $LINENO <<"!"
L reverse search isn't canceled after an interrupt in vi mode

d 15
p :test-1:
w echo WRONG
p :test-2:
w print CORREC
p :test-3:
w echo foo
p :test-4:
w sleep 0
p :test-5:
c e\E[A\E[A\cC\E[A\E[A\E[A
w $aT
u CORRECT
!

((SHOPT_ESH)) && VISUAL=emacs tst $LINENO <<"!"
L failure to start new reverse search in emacs mode
# https://github.com/ksh93/ksh/commit/b5e52703

d 15
p :test-1:
w echo WRON
p :test-2:
w print CORREC
p :test-3:
w e\E[AG
u WRONG
p :test-4:
w p\E[AT
u CORRECT
!

((SHOPT_VSH)) && tst $LINENO <<"!"
L backwards reverse search in vi mode

d 15
p :test-1:
w print bar
p :test-2:
w print foo
p :test-3:
w echo WRONG
p :test-4:
w print Correc
p :test-5:
c p\E[A\E[A\E[A\E[B\E[B
w $at
u Correct
!

((SHOPT_ESH)) && VISUAL=emacs tst $LINENO <<"!"
L backwards reverse search in emacs mode

d 15
p :test-1:
w print bar
p :test-2:
w print foo
p :test-3:
w echo WRONG
p :test-4:
w print Correc
p :test-5:
c p\E[A\E[A\E[A\E[B\E[B
w t
u Correct
!

# needs non-dumb terminal for multiline editing
((multiline && SHOPT_ESH)) && mkdir -p fullcomplete/foe && VISUAL=emacs TERM=vt100 tst $LINENO <<"!"
L full-word completion in emacs mode
# https://github.com/ksh93/ksh/pull/580

d 15
p :test-1:
w true fullcomplete/foi\cb\t
r ^:test-1: true fullcomplete/foi\r\n
p :test-2:
w true fullcomplete/foi\cb=
r ^:test-2: true fullcomplete/foi\r\n
p :test-3:
w true fullcomplete/foi\cb*
r ^:test-3: true fullcomplete/foi\r\n
!

# needs non-dumb terminal for multiline editing
((multiline && SHOPT_VSH)) && mkdir -p fullcomplete/fov && VISUAL=vi TERM=vt100 tst $LINENO <<"!"
L full-word completion in vi mode
# https://github.com/ksh93/ksh/pull/580

d 40
p :test-1:
w true fullcomplete/foi\Eh\\a
r ^:test-1: true fullcomplete/foi\r\n
p :test-2:
w true fullcomplete/foi\Eh=a
r ^:test-2: true fullcomplete/foi\r\n
p :test-3:
w true fullcomplete/foi\Eh*a
r ^:test-3: true fullcomplete/foi\r\n
!

((SHOPT_VSH && SHOPT_MULTIBYTE)) &&
[[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]] &&
mkdir -p vitest/aあb && VISUAL=vi tst $LINENO <<"!"
L vi completion from wide produces corrupt characters
# https://github.com/ksh93/ksh/issues/571

d 40
p :test-1:
w cd vitest/aあ\t
r ^:test-1: cd vitest/aあb/\r\n$
!

((SHOPT_HISTEXPAND && (SHOPT_VSH || SHOPT_ESH))) &&
mkdir -p 'chrtest/aa#b' && tst $LINENO <<"!"
L tab-completing with first histchar

d 40
p :test-1:
w histchars='#^!'
p :test-2:
w set +o histexpand
p :test-3:
w ls chrtest/a\t
r ^:test-3: ls chrtest/aa#b/\r\n$
p :test-4:
w set -o histexpand
p :test-5:
w ls chrtest/a\t
r ^:test-5: ls chrtest/aa\\#b/\r\n$
p :test-6:
w unset histchars
!

((SHOPT_HISTEXPAND && (SHOPT_VSH || SHOPT_ESH))) &&
mkdir -p 'chrtest2/@a@b' && tst $LINENO <<"!"
L tab-completing with third histchar

d 40
p :test-1:
w histchars='!^@'
p :test-2:
w cd chrtest2
p :test-3:
w set +o histexpand
p :test-4:
w ls \t
r ^:test-4: ls @a@b/\r\n$
p :test-5:
w set -o histexpand
p :test-6:
w ls \t
r ^:test-6: ls \\@a@b/\r\n$
!

((SHOPT_VSH || SHOPT_ESH)) &&
mkdir -p 'chrtest3/~ab' && tst $LINENO <<"!"
L tab-completing with escaped ~

d 40
p :test-1:
w cd chrtest3; .sh.tilde.get() { print -n WRONG_TILDE_EXPANSION >&2; };
p :test-2:
w ls \\~\t
r ^:test-2: ls \\~ab/\r\n$
p :test-3:
w ls '~\t
r ^:test-3: ls \\~ab/\r\n$
p :test-4:
w ls "~\t
r ^:test-4: ls \\~ab/\r\n$
p :test-5:
w ls $'~\t
r ^:test-5: ls \\~ab/\r\n$
!

((SHOPT_VSH || SHOPT_ESH)) &&
chmod +x cmd_complete_me >cmd_complete_me &&
PATH=.:$PATH tst $LINENO <<"!"
L command completion after init and after TERM change
# https://github.com/ksh93/ksh/issues/642

d 40
p :test-1:
w cmd_complet\t
r cmd_complete_me \r\n$
# also try after TERM change
p :test-2:
w TERM=ansi
p :test-3:
w cmd_complet\t
r cmd_complete_me \r\n$
!

((SHOPT_VSH || SHOPT_ESH)) &&
echo "function _ksh_93u_m_cmdcomplete_test_ { echo RUN; }" > _ksh_93u_m_cmdcomplete_test_ &&
FPATH=$PWD tst $LINENO <<"!"
L function and builtin completion when a function is undefined
# https://github.com/ksh93/ksh/issues/650

d 40
p :test-1:
w _ksh_93u_m_cmdcomplete_test_; autoload _a_nonexistent_function_
u ^RUN\r\n$
p :test-2:
w _ksh_93u_m_cmdcompl\t
r :test-2: _ksh_93u_m_cmdcomplete_test_ \r\n$
!

# ======
exit $((Errors<125?Errors:125))
