/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   solve.c                                            :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

int	cmd_disorder(int ac, char **av)
{
	t_stack		a;
	long long	bad;
	long long	tot;
	int			i;
	int			j;

	if (!parse_stack(ac, av, &a))
		return (fprintf(stderr, "Error\n"), 1);
	bad = 0;
	tot = 0;
	i = -1;
	while (++i < a.n)
	{
		j = i;
		while (++j < a.n)
		{
			tot++;
			bad += a.v[i] > a.v[j];
		}
	}
	if (tot)
		printf("%.2f\n", 100.0 * (double)bad / (double)tot);
	else
		printf("%.2f\n", 0.0);
	return (0);
}

static int	find_min(t_stack *a)
{
	int	i;
	int	mi;

	mi = 0;
	i = 1;
	while (i < a->n)
	{
		if (a->v[i] < a->v[mi])
			mi = i;
		i++;
	}
	return (mi);
}

static void	bring_to_top(t_stack *a, int mi)
{
	while (mi != 0)
	{
		if (mi <= a->n / 2)
		{
			puts("ra");
			rot(a);
			mi--;
		}
		else
		{
			puts("rra");
			rrot(a);
			mi = (mi + 1) % a->n;
		}
	}
}

/* Selection sort: rotate min to top, pb, repeat; then pa everything. */
int	cmd_solve(int ac, char **av)
{
	t_stack	a;
	t_stack	b;
	int		pushed;

	if (!parse_stack(ac, av, &a))
		return (fprintf(stderr, "Error\n"), 1);
	b.v = malloc(sizeof(long) * (a.n + 1));
	b.n = 0;
	pushed = 0;
	while (a.n > 0)
	{
		bring_to_top(&a, find_min(&a));
		puts("pb");
		push(&b, &a);
		pushed++;
	}
	while (pushed--)
		puts("pa");
	return (0);
}
