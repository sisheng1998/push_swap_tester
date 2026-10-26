/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   mix.c                                              :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

/* Picks k random distinct positions into pos[0..k). */
static void	pick_positions(int *pos, int n, int k)
{
	int	i;
	int	j;
	int	t;

	i = 0;
	while (i < n)
	{
		pos[i] = i;
		i++;
	}
	i = 0;
	while (i < k)
	{
		j = i + (int)rnd(0, n - 1 - i);
		t = pos[i];
		pos[i] = pos[j];
		pos[j] = t;
		i++;
	}
}

/* Shuffles the values sitting at the k picked positions. */
static void	shuffle_positions(long *v, int *pos, int k)
{
	int		i;
	int		j;
	long	t;

	i = k - 1;
	while (i > 0)
	{
		j = (int)rnd(0, i);
		t = v[pos[i]];
		v[pos[i]] = v[pos[j]];
		v[pos[j]] = t;
		i--;
	}
}

int	cmd_mix(int n, int pct)
{
	int		*pos;
	long	*v;
	int		i;

	v = malloc(sizeof(long) * (n + 1));
	pos = malloc(sizeof(int) * (n + 1));
	i = 0;
	while (i < n)
	{
		v[i] = i - n / 2;
		i++;
	}
	pick_positions(pos, n, n * pct / 100);
	shuffle_positions(v, pos, n * pct / 100);
	print_list(v, n);
	free(v);
	free(pos);
	return (0);
}
