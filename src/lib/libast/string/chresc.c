/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2013 AT&T Intellectual Property          *
*          Copyright (c) 2020-2024 Contributors to ksh 93u+m           *
*                      and is licensed under the                       *
*                 Eclipse Public License, Version 2.0                  *
*                                                                      *
*                A copy of the License is available at                 *
*      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      *
*         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         *
*                                                                      *
*                 Glenn Fowler <gsf@research.att.com>                  *
*                  David Korn <dgk@research.att.com>                   *
*                   Phong Vo <kpv@research.att.com>                    *
*                  Martijn Dekker <martijn@inlv.org>                   *
*                                                                      *
***********************************************************************/
/*
 * Glenn Fowler
 * AT&T Research
 *
 * return the next character in the string s
 * \ character constants are expanded
 * *p is updated to point to the next character in s
 * *m is 1 if return value is wide
 */

#include <ast.h>
#include <ctype.h>

#include <ccode.h>
#include <regex.h>

int
chrexp(const char* s, char** p, int* m, int flags)
{
	const char*	q;
	int		c;
	const char*	e;
	const char*	b;
	char*		r;
	int		n;
	int		w;

	w = 0;
	for (;;)
	{
		b = s;
		switch (c = mbchar(s))
		{
		case 0:
			s--;
			break;
		case '\\':
			switch (c = *s++)
			{
			case '0': case '1': case '2': case '3':
			case '4': case '5': case '6': case '7':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c -= '0';
				q = s + 2;
				while (s < q)
					switch (*s)
					{
					case '0': case '1': case '2': case '3':
					case '4': case '5': case '6': case '7':
						c = (c << 3) + *s++ - '0';
						break;
					default:
						q = s;
						break;
					}
				break;
			case 'a':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c = CC_bel;
				break;
			case 'b':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c = '\b';
				break;
			case 'c': /*DEPRECATED*/
			case 'C':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				if (c = *s)
				{
					s++;
					if (c == '\\')
					{
						c = chrexp(s - 1, &r, 0, flags);
						s = (const char*)r;
					}
					if (islower(c))
						c = toupper(c);
					c = ccmapc(c, CC_NATIVE, CC_ASCII);
					c ^= 0x40;
					c = ccmapc(c, CC_ASCII, CC_NATIVE);
				}
				break;
			case 'e': /*DEPRECATED*/
			case 'E':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c = CC_esc;
				break;
			case 'f':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c = '\f';
				break;
			case 'M':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				if (*s == '-')
				{
					s++;
					c = CC_esc;
				}
				break;
			case 'n':
				if (flags & FMT_EXP_NONL)
					continue;
				if (!(flags & FMT_EXP_LINE))
					goto noexpand;
				c = '\n';
				break;
			case 'r':
				if (flags & FMT_EXP_NOCR)
					continue;
				if (!(flags & FMT_EXP_LINE))
					goto noexpand;
				c = '\r';
				break;
			case 't':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c = '\t';
				break;
			case 'v':
				if (!(flags & FMT_EXP_CHAR))
					goto noexpand;
				c = CC_vt;
				break;
			case 'u':
				q = s + 4;
				goto wex;
			case 'U':
				q = s + 8;
			wex:
				if (!(flags & FMT_EXP_WIDE))
					goto noexpand;
				w = 1;
				goto hex;
			case 'x':
				q = s + 2;
			hex:
				b = e = s;
				n = 0;
				c = 0;
				while (!e || !q || s < q)
				{
					switch (*s)
					{
					case 'a': case 'b': case 'c': case 'd': case 'e': case 'f':
						c = (c << 4) + *s++ - 'a' + 10;
						n++;
						continue;
					case 'A': case 'B': case 'C': case 'D': case 'E': case 'F':
						c = (c << 4) + *s++ - 'A' + 10;
						n++;
						continue;
					case '0': case '1': case '2': case '3': case '4':
					case '5': case '6': case '7': case '8': case '9':
						c = (c << 4) + *s++ - '0';
						n++;
						continue;
					case '{':
					case '[':
						if (s != e)
							break;
						e = 0;
						s++;
						if (w && *s == 'U' && *(s + 1) == '+')
							s += 2;
						continue;
					case '}':
					case ']':
						if (!e)
							s++;
						break;
					default:
						break;
					}
					break;
				}
				if (n <= 2 && !(flags & FMT_EXP_CHAR) || n > 2 && (w = 1) && !(flags & FMT_EXP_WIDE))
				{
					c = '\\';
					s = b;
				}
				break;
			case 0:
				s--;
				break;
			}
			break;
		default:
			if ((s - b) > 1)
				w = 1;
			break;
		}
		break;
	}
 normal:
	if (p)
		*p = (char*)s;
	if (m)
		*m = w;
	return c;
 noexpand:
	c = '\\';
	s--;
	goto normal;
}

int
chresc(const char* s, char** p)
{
	return chrexp(s, p, NULL, FMT_EXP_CHAR|FMT_EXP_LINE|FMT_EXP_WIDE);
}
