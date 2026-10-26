/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   ops.c                                              :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

void	swap(t_stack *s)
{
	long	t;

	if (s->n < 2)
		return ;
	t = s->v[0];
	s->v[0] = s->v[1];
	s->v[1] = t;
}

void	push(t_stack *dst, t_stack *src)
{
	if (!src->n)
		return ;
	memmove(dst->v + 1, dst->v, sizeof(long) * dst->n);
	dst->v[0] = src->v[0];
	dst->n++;
	src->n--;
	memmove(src->v, src->v + 1, sizeof(long) * src->n);
}

void	rot(t_stack *s)
{
	long	t;

	if (s->n < 2)
		return ;
	t = s->v[0];
	memmove(s->v, s->v + 1, sizeof(long) * (s->n - 1));
	s->v[s->n - 1] = t;
}

void	rrot(t_stack *s)
{
	long	t;

	if (s->n < 2)
		return ;
	t = s->v[s->n - 1];
	memmove(s->v + 1, s->v, sizeof(long) * (s->n - 1));
	s->v[0] = t;
}
