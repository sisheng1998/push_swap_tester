/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   rand.c                                             :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

void	seed_rng(void)
{
	const char	*s;

	s = getenv("SEED");
	if (s && *s)
		srandom((unsigned)strtoul(s, NULL, 10));
	else
		srandom((unsigned)time(NULL) ^ ((unsigned)getpid() << 16));
}

long	rnd(long lo, long hi)
{
	unsigned long long	r;

	r = ((unsigned long long)random() << 31) ^ (unsigned long long)random();
	return (lo + (long)(r % (unsigned long long)(hi - lo + 1)));
}

void	print_list(long *v, int n)
{
	int	i;

	i = 0;
	while (i < n)
	{
		if (i)
			printf(" ");
		printf("%ld", v[i]);
		i++;
	}
	printf("\n");
}

int	cmd_randops(int k)
{
	while (k-- > 0)
		puts(op_name(rnd(0, 10)));
	return (0);
}
