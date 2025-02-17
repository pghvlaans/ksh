/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1985-2011 AT&T Intellectual Property          *
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
#include	"sfhdr.h"

/*	Read a record delineated by a character.
**	The record length can be accessed via sfvalue(f).
**
**	Written by Kiem-Phong Vo
*/

char* sfgetr(Sfio_t*	f,	/* stream to read from	*/
	     int	rc,	/* record separator	*/
	     int	type)
{
	ssize_t		n, un;
	uchar		*s, *ends, *us;
	int		found;
	Sfrsrv_t*	rsrv;

	if(!f || rc < 0 || (f->mode != SFIO_READ && _sfmode(f,SFIO_READ,0) < 0))
		return NULL;
	SFLOCK(f,0);

	/* buffer to be returned */
	rsrv = NULL;
	us = NULL;
	un = 0;
	found = 0;

	/* compatibility mode */
	type = type < 0 ? SFIO_LASTR : type == 1 ? SFIO_STRING : type;

	if(type&SFIO_LASTR) /* return the broken record */
	{	if((f->flags&SFIO_STRING) && (un = f->endb - f->next))
		{	us = f->next;
			f->next = f->endb;
			found = 1;
		}
		else if((rsrv = f->rsrv) && (un = -rsrv->slen) > 0)
		{	us = rsrv->data;
			found = 1;
		}
		goto done;
	}

	while(!found)
	{	/* fill buffer if necessary */
		if((n = (ends = f->endb) - (s = f->next)) <= 0)
		{	/* for unseekable devices, peek-read 1 record */
			f->getr = rc;
			f->mode |= SFIO_RC;

			/* fill buffer the conventional way */
			if(SFRPEEK(f,s,n) <= 0)
			{	us = NULL;
				goto done;
			}
			else
			{	ends = s+n;
				if(f->mode&SFIO_RC)
				{	s = ends[-1] == rc ? ends-1 : ends;
					goto do_copy;
				}
			}
		}

		if(!(s = (uchar*)memchr((char*)s,rc,n)))
			s = ends;
	do_copy:
		if(s < ends) /* found separator */
		{	s += 1;		/* include the separator */
			found = 1;

			if(!us &&
			   (!(type&SFIO_STRING) || !(f->flags&SFIO_STRING) ||
			    ((f->flags&SFIO_STRING) && (f->bits&SFIO_BOTH) ) ) )
			{	/* returning data in buffer */
				us = f->next;
				un = s - f->next;
				f->next = s;
				goto done;
			}
		}

		/* amount to be read */
		n = s - f->next;

		if(!found && (_Sfmaxr > 0 && un+n+1 >= _Sfmaxr || (f->flags&SFIO_STRING))) /* already exceed limit */
		{	us = NULL;
			goto done;
		}

		/* get internal buffer */
		if(!rsrv || rsrv->size < un+n+1)
		{	if(rsrv)
				rsrv->slen = un;
			if((rsrv = _sfrsrv(f,un+n+1)) != NULL)
				us = rsrv->data;
			else
			{	us = NULL;
				goto done;
			}
		}

		/* now copy data */
		s = us+un;
		un += n;
		ends = f->next;
		f->next += n;
		MEMCPY(s,ends,n);
	}

done:
	_Sfi = f->val = un;
	f->getr = 0;
	if(found && rc != 0 && (type&SFIO_STRING) )
	{	us[un-1] = '\0';
		if(us >= f->data && us < f->endb)
		{	f->getr = rc;
			f->mode |= SFIO_GETR;
		}
	}

	/* prepare for a call to get the broken record */
	if(rsrv)
		rsrv->slen = found ? 0 : -un;

	SFOPEN(f,0);

	if(us && (type&SFIO_LOCKR) )
	{	f->mode |= SFIO_PEEK|SFIO_GETR;
		f->endr = f->data;
	}

	return (char*)us;
}
