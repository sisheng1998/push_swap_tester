/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   check.c                                            :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

static int	run_line(char *line, int len, t_stack *a, t_stack *b)
{
	line[len] = 0;
	return (apply(line, a, b));
}

static int	read_ops(t_stack *a, t_stack *b)
{
	char	line[64];
	int		c;
	int		len;

	len = 0;
	c = getchar();
	while (c != EOF)
	{
		if (c == '\n')
		{
			if (!run_line(line, len, a, b))
				return (0);
			len = 0;
		}
		else if (len < 63)
			line[len++] = (char)c;
		else
			return (0);
		c = getchar();
	}
	if (len && !run_line(line, len, a, b))
		return (0);
	return (1);
}

static int	is_sorted(t_stack *a)
{
	int	i;

	i = 1;
	while (i < a->n)
	{
		if (a->v[i - 1] > a->v[i])
			return (0);
		i++;
	}
	return (1);
}

int	cmd_check(int ac, char **av)
{
	t_stack	a;
	t_stack	b;

	if (ac == 0)
		return (0);
	if (!parse_stack(ac, av, &a))
		return (fprintf(stderr, "Error\n"), 1);
	b.v = malloc(sizeof(long) * (a.n + 1));
	b.n = 0;
	if (!read_ops(&a, &b))
		return (fprintf(stderr, "Error\n"), 1);
	if (is_sorted(&a) && !b.n)
		puts("OK");
	else
		puts("KO");
	return (0);
}
