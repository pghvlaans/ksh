/***********************************************************************
*                                                                      *
*               This software is part of the ast package               *
*          Copyright (c) 1982-2012 AT&T Intellectual Property          *
*          Copyright (c) 2020-2022 Contributors to ksh 93u+m           *
*                      and is licensed under the                       *
*                 Eclipse Public License, Version 2.0                  *
*                                                                      *
*                A copy of the License is available at                 *
*      https://www.eclipse.org/org/documents/epl-2.0/EPL-2.0.html      *
*         (with md5 checksum 84283fa8859daf213bdda5a9f8d1be1d)         *
*                                                                      *
*                  David Korn <dgk@research.att.com>                   *
*                  Martijn Dekker <martijn@inlv.org>                   *
*            Johnothan King <johnothanking@protonmail.com>             *
*                                                                      *
***********************************************************************/
#include	"shopt.h"
#include	"defs.h"
#include	<stak.h>
#include	<ls.h>
#include	<error.h>
#include	"variables.h"
#include	"io.h"
#include	"name.h"
#include	"history.h"
#include	"builtins.h"
#if SHOPT_HISTEXPAND
#   include	"edit.h"
#endif

#define HIST_RECURSE	5

static void hist_subst(const char*, int fd, char*);

#if 0
    /* for the benefit of the dictionary generator */
    int	b_fc(int argc,char *argv[], Shbltin_t *context){}
#endif
int	b_hist(int argc,char *argv[], Shbltin_t *context)
{
	register History_t *hp;
	register char *arg;
	register int flag,fdo,cdo;
	Sfio_t *outfile,*coutfile;
	char *fname,*cname;
	int range[2], incr, index2, indx= -1;
	char *edit = 0;		/* name of editor */
	char *replace = 0;	/* replace old=new */
	int lflag = 0, nflag = 0, rflag = 0;
#if SHOPT_HISTEXPAND
	int pflag = 0;
#endif
	Histloc_t location;
	NOT_USED(argc);
	NOT_USED(context);
	if(!sh_histinit())
	{
		errormsg(SH_DICT,ERROR_system(1),e_histopen);
		UNREACHABLE();
	}
	hp = sh.hist_ptr;
	while((flag = optget(argv,sh_opthist))) switch(flag)
	{
	    case 'e':
		edit = opt_info.arg;
		break;
	    case 'n':
		nflag++;
		break;
	    case 'l':
		lflag = 1;
		break;
	    case 'r':
		rflag++;
		break;
	    case 's':
		edit = "-";
		break;
#if SHOPT_HISTEXPAND
	    case 'p':
		pflag++;
		break;
#endif
	    case 'N':
		if(indx<=0)
		{
			if((flag = hist_max(hp) - opt_info.num-1) < 0)
				flag = 1;
			range[++indx] = flag;
			break;
		}
		/* FALLTHROUGH */
	    case ':':
		errormsg(SH_DICT,2, "%s", opt_info.arg);
		break;
	    case '?':
		errormsg(SH_DICT,ERROR_usage(2), "%s", opt_info.arg);
		UNREACHABLE();
	}
	if(error_info.errors)
	{
		errormsg(SH_DICT,ERROR_usage(2),"%s",optusage((char*)0));
		UNREACHABLE();
	}
	argv += (opt_info.index-1);
#if SHOPT_HISTEXPAND
	if(pflag)
	{
		hist_cancel(hp);
		pflag = 0;
		while(arg=argv[1])
		{
			flag = hist_expand(arg,&replace);
			if(!(flag & HIST_ERROR))
				sfputr(sfstdout, replace, '\n');
			else
				pflag = 1;
			if(replace)
				free(replace);
			argv++;
		}
		return pflag;
	}
#endif
	flag = indx;
	while(flag<1 && (arg=argv[1]))
	{
		/* look for old=new argument */
		if(!replace && strchr(arg+1,'='))
		{
			replace = arg;
			argv++;
			continue;
		}
		else if(isdigit(*arg) || *arg == '-')
		{
			/* see if completely numeric */
			do	arg++;
			while(isdigit(*arg));
			if(*arg==0)
			{
				arg = argv[1];
				range[++flag] = (int)strtol(arg, (char**)0, 10);
				if(*arg == '-')
					range[flag] += (hist_max(hp)-1);
				argv++;
				continue;
			}
		}
		/* search for last line starting with string */
		location = hist_find(hp,argv[1],hist_max(hp)-1,0,-1);
		if((range[++flag] = location.hist_command) < 0)
		{
			errormsg(SH_DICT,ERROR_exit(1),e_found,argv[1]);
			UNREACHABLE();
		}
		argv++;
	}
	if(flag <0)
	{
		/* set default starting range */
		if(lflag)
		{
			flag = hist_max(hp)-16;
			if(flag<1)
				flag = 1;
		}
		else
			flag = hist_max(hp)-2;
		range[0] = flag;
		flag = 0;
	}
	index2 = hist_min(hp);
	if(range[0]<index2)
		range[0] = index2;
	if(flag==0)
		/* set default termination range */
		range[1] = ((lflag && !edit)?hist_max(hp)-1:range[0]);
	if(range[1]>=(flag=(hist_max(hp) - !lflag)))
		range[1] = flag;
	/* check for valid ranges */
	if(range[1]<index2 || range[0]>=flag)
	{
		errormsg(SH_DICT,ERROR_exit(1),e_badrange,range[0],range[1]);
		UNREACHABLE();
	}
	if(edit && *edit=='-' && range[0]!=range[1])
	{
		errormsg(SH_DICT,ERROR_exit(1),e_eneedsarg);
		UNREACHABLE();
	}
	/* now list commands from range[flag] to range[1-flag] */
	incr = 1;
	flag = rflag>0;
	if(range[1-flag] < range[flag])
		incr = -1;
	if(lflag)
	{
		outfile = sfstdout;
		arg = "\n\t";
	}
	else
	{
		if(!(fname=pathtmp(NIL(char*),0,0,NIL(int*))))
		{
			errormsg(SH_DICT,ERROR_exit(1),e_create,"");
			UNREACHABLE();
		}
		if((fdo=open(fname,O_CREAT|O_RDWR,S_IRUSR|S_IWUSR)) < 0)
		{
			errormsg(SH_DICT,ERROR_system(1),e_create,fname);
			UNREACHABLE();
		}
		outfile= sfnew(NIL(Sfio_t*),sh.outbuff,IOBSIZE,fdo,SF_WRITE);
		arg = "\n";
		nflag++;
	}
	while(1)
	{
		if(nflag==0)
			sfprintf(outfile,"%d\t",range[flag]);
		else if(lflag)
			sfputc(outfile,'\t');
		hist_list(sh.hist_ptr,outfile,hist_tell(sh.hist_ptr,range[flag]),0,arg);
		if(!(cname=pathtmp(NIL(char*),0,0,NIL(int*))))
		{
			errormsg(SH_DICT,ERROR_exit(1),e_create,"");
			UNREACHABLE();
		}
		if((cdo=open(cname,O_CREAT|O_RDWR,S_IRUSR|S_IWUSR)) < 0)
		{
			errormsg(SH_DICT,ERROR_system(1),e_create,cname);
			UNREACHABLE();
		}
		sh_iosave(fdo,sh.topfd,cname);
		coutfile= sfnew(NIL(Sfio_t*),sh.outbuff,IOBSIZE,cdo,SF_WRITE);
		hist_list(sh.hist_ptr,coutfile,hist_tell(sh.hist_ptr,range[flag]),0,arg);
		if(lflag)
			sh_sigcheck();
		if(range[flag] == range[1-flag])
			break;
		range[flag] += incr;
	}
	if(lflag)
		return(0);
	sfclose(outfile);
	hist_eof(hp);
	arg = edit;
	if(!arg && !(arg=nv_getval(sh_scoped(HISTEDIT))) && !(arg=nv_getval(sh_scoped(FCEDNOD))))
	{
		arg = (char*)e_defedit;
		if(*arg!='/')
		{
			errormsg(SH_DICT,ERROR_exit(1),"ed not found set FCEDIT");
			UNREACHABLE();
		}
	}
	char differ=1;
	if(*arg != '-')
	{
		char *com[3],*dcom[5];
		com[0] =  arg;
		com[1] =  fname;
		com[2] = 0;
		error_info.errors = sh_eval(sh_sfeval(com),0);

		dcom[0] =  "cmp";
		dcom[1] =  fname;
		dcom[2] =  cname;
		dcom[3] =  "> /dev/null";
		dcom[4] = 0;
		differ = sh_eval(sh_sfeval(dcom),0);
	}
	fdo = sh_chkopen(fname);
	unlink(fname);
	free((void*)fname);
	cdo = sh_chkopen(cname);
	unlink(cname);
	free((void*)cname);
	/* don't history fc itself unless forked */
	error_info.flags |= ERROR_SILENT;
	if(!sh_isstate(SH_FORKED))
		hist_cancel(hp);
	sh_onstate(SH_HISTORY);
	sh_onstate(SH_VERBOSE);	/* echo lines as read */
	if(replace)
	{
		hist_subst(error_info.id,fdo,replace);
		sh_close(fdo);
		sh_close(cdo);
	}
	else if(error_info.errors == 0)
	{
		char buff[IOBSIZE+1],cbuff[IOBSIZE+1];
		Sfio_t *iop,*cop;
		/* read in and run the command */
		if(sh.hist_depth++ > HIST_RECURSE)
		{
			sh_close(fdo);
			sh_close(cdo);
			errormsg(SH_DICT,ERROR_exit(1),e_toodeep,"history");
			UNREACHABLE();
		}
		iop = sfnew(NIL(Sfio_t*),buff,IOBSIZE,fdo,SF_READ);
		if(differ)
			sh_eval(iop,1);  /* this will close fdo */
		else
		{
			hist_cancel(hp);
			sh_close(fdo);
		}
		sh.hist_depth--;
		sh_close(cdo);
	}
	else
	{
		sh_close(fdo);
		sh_close(cdo);
		if(!sh_isoption(SH_VERBOSE))
			sh_offstate(SH_VERBOSE);
		sh_offstate(SH_HISTORY);
	}
	return(sh.exitval);
}


/*
 * given a file containing a command and a string of the form old=new,
 * execute the command with the string old replaced by new
 */
static void hist_subst(const char *command,int fd,char *replace)
{
	register char *newp=replace;
	register char *sp;
	register int c;
	off_t size;
	char *string;
	while(*++newp != '='); /* skip to '=' */
	if((size = lseek(fd,(off_t)0,SEEK_END)) < 0)
		return;
	lseek(fd,(off_t)0,SEEK_SET);
	c =  (int)size;
	string = stakalloc(c+1);
	if(read(fd,string,c)!=c)
		return;
	string[c] = 0;
	*newp++ =  0;
	if((sp=sh_substitute(string,replace,newp))==0)
	{
		sh_close(fd);
		errormsg(SH_DICT,ERROR_exit(1),e_subst,command);
		UNREACHABLE();
	}
	*(newp-1) =  '=';
	sh_eval(sfopen(NIL(Sfio_t*),sp,"s"),1);
}
