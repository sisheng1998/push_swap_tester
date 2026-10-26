/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   ps_tool.h                                          :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#ifndef PS_TOOL_H
# define PS_TOOL_H

# include <errno.h>
# include <limits.h>
# include <stdio.h>
# include <stdlib.h>
# include <string.h>
# include <time.h>
# include <unistd.h>

typedef struct s_stack
{
	long	*v;
	int		n;
}	t_stack;

int			parse_stack(int ac, char **av, t_stack *a);
void		swap(t_stack *s);
void		push(t_stack *dst, t_stack *src);
void		rot(t_stack *s);
void		rrot(t_stack *s);
int			apply(const char *op, t_stack *a, t_stack *b);
const char	*op_name(int i);
void		seed_rng(void);
long		rnd(long lo, long hi);
void		print_list(long *v, int n);
int			cmd_check(int ac, char **av);
int			cmd_gen(int n, long lo, long hi);
int			cmd_mix(int n, int pct);
int			cmd_disorder(int ac, char **av);
int			cmd_solve(int ac, char **av);
int			cmd_randops(int k);

#endif
