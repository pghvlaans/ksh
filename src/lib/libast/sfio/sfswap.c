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
*            Johnothan King <johnothanking@protonmail.com>             *
*                                                                      *
***********************************************************************/
#include	"sfhdr.h"

/*	Swap two streams. If the second argument is NULL,
**	a new stream will be created. Always return the second argument
**	or the new stream. Note that this function will always work
**	unless streams are locked by SFIO_PUSH.
**
**	Written by Kiem-Phong Vo.
*/

Sfio_t* sfswap(Sfio_t* f1, Sfio_t* f2)
{
	Sfio_t		tmp;
	int		f1pool, f2pool, f1flags, f2flags;
	unsigned int	f1mode, f2mode;

	if(!f1 || (f1->mode&SFIO_AVAIL) || (SFFROZEN(f1) && (f1->mode&SFIO_PUSH)) )
		return NULL;
	if(f2 && SFFROZEN(f2) && (f2->mode&SFIO_PUSH) )
		return NULL;
	if(f1 == f2)
		return f2;

	f1mode = f1->mode;
	SFLOCK(f1,0);
	f1->mode |= SFIO_PUSH;		/* make sure there is no recursion on f1 */
	
	if(f2)
	{	f2mode = f2->mode;
		SFLOCK(f2,0);
		f2->mode |= SFIO_PUSH;	/* make sure there is no recursion on f2 */
	}
	else
	{	f2 = f1->file == 0 ? sfstdin :
		     f1->file == 1 ? sfstdout :
		     f1->file == 2 ? sfstderr : NULL;
		if((!f2 || !(f2->mode&SFIO_AVAIL)) )
		{	if(!(f2 = (Sfio_t*)malloc(sizeof(Sfio_t))) )
			{	f1->mode = f1mode;
				SFOPEN(f1,0);
				return NULL;
			}

			SFCLEAR(f2);
		}
		f2->mode = SFIO_AVAIL|SFIO_LOCK;
		f2mode = SFIO_AVAIL;
	}

	if(!f1->pool)
		f1pool = -1;
	else for(f1pool = f1->pool->n_sf-1; f1pool >= 0; --f1pool)
		if(f1->pool->sf[f1pool] == f1)
			break;
	if(!f2->pool)
		f2pool = -1;
	else for(f2pool = f2->pool->n_sf-1; f2pool >= 0; --f2pool)
		if(f2->pool->sf[f2pool] == f2)
			break;

	f1flags = f1->flags;
	f2flags = f2->flags;

	/* swap image and pool entries */
	memcpy(&tmp,f1,sizeof(Sfio_t));
	memcpy(f1,f2,sizeof(Sfio_t));
	memcpy(f2,&tmp,sizeof(Sfio_t));
	if(f2pool >= 0)
		f1->pool->sf[f2pool] = f1;
	if(f1pool >= 0)
		f2->pool->sf[f1pool] = f2;

	if(f2flags&SFIO_STATIC)
		f2->flags |= SFIO_STATIC;
	else	f2->flags &= ~SFIO_STATIC;

	if(f1flags&SFIO_STATIC)
		f1->flags |= SFIO_STATIC;
	else	f1->flags &= ~SFIO_STATIC;

	if(f2mode&SFIO_AVAIL)	/* swapping to a closed stream */
	{	if(!(f1->flags&SFIO_STATIC) )
			free(f1);
	}
	else
	{	f1->mode = f2mode;
		SFOPEN(f1,0);
	}

	f2->mode = f1mode;
	SFOPEN(f2,0);
	return f2;
}
