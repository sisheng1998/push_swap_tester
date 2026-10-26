/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   apply.c                                            :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

const char	*op_name(int i)
{
	const char	*ops[] = {"sa", "sb", "ss", "pa", "pb", "ra", "rb",
		"rr", "rra", "rrb", "rrr"};

	return (ops[i]);
}

/* ss / rr / rrr hit both the a and the b case. */
int	apply(const char *op, t_stack *a, t_stack *b)
{
	int	i;

	i = 0;
	while (i < 11 && strcmp(op, op_name(i)))
		i++;
	if (i == 11)
		return (0);
	if (i == 0 || i == 2)
		swap(a);
	if (i == 1 || i == 2)
		swap(b);
	if (i == 3)
		push(a, b);
	if (i == 4)
		push(b, a);
	if (i == 5 || i == 7)
		rot(a);
	if (i == 6 || i == 7)
		rot(b);
	if (i == 8 || i == 10)
		rrot(a);
	if (i == 9 || i == 10)
		rrot(b);
	return (1);
}
