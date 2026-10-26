/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   gen.c                                              :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

/* Small range: partial Fisher-Yates over every value in [lo, lo+range). */
static void	gen_dense(long *v, int n, long lo, long range)
{
	long	i;
	long	k;
	long	t;

	i = 0;
	while (i < range)
	{
		v[i] = lo + i;
		i++;
	}
	i = 0;
	while (i < n)
	{
		k = i + (int)rnd(0, range - 1 - i);
		t = v[i];
		v[i] = v[k];
		v[k] = t;
		i++;
	}
}

/* Huge range: draw and retry on duplicates. */
static void	gen_sparse(long *v, int n, long lo, long hi)
{
	int	i;
	int	j;

	i = 0;
	while (i < n)
	{
		v[i] = rnd(lo, hi);
		j = 0;
		while (j < i && v[j] != v[i])
			j++;
		if (j == i)
			i++;
	}
}

int	cmd_gen(int n, long lo, long hi)
{
	long	*v;
	long	range;

	range = hi - lo + 1;
	if (n < 0 || range < n)
		return (fprintf(stderr, "gen: range too small\n"), 1);
	if (range <= 2000000)
	{
		v = malloc(sizeof(long) * range);
		gen_dense(v, n, lo, range);
	}
	else
	{
		v = malloc(sizeof(long) * (n + 1));
		gen_sparse(v, n, lo, hi);
	}
	print_list(v, n);
	free(v);
	return (0);
}
