/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   main.c                                             :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

/*
** ps_tool - helper for push_swap_tester (not part of any 42 submission).
**
**   ps_tool gen N [MIN MAX]      N unique random ints in [MIN, MAX]
**   ps_tool mix N PCT            sorted list with PCT% of positions shuffled
**   ps_tool disorder ARGS...     disorder of ARGS as a percentage (%.2f)
**   ps_tool check ARGS... < ops  reference checker: OK / KO / Error
**   ps_tool solve ARGS...        prints a (naive) valid sorting sequence
**   ps_tool randops K            prints K random valid instructions
**
** Seed with the SEED environment variable for reproducible runs.
*/
#include "ps_tool.h"

static int	run_gen(int ac, char **av)
{
	long	lo;
	long	hi;

	lo = INT_MIN;
	hi = INT_MAX;
	if (ac > 3)
		lo = atol(av[3]);
	if (ac > 4)
		hi = atol(av[4]);
	return (cmd_gen(atoi(av[2]), lo, hi));
}

int	main(int ac, char **av)
{
	if (ac < 2)
		return (fprintf(stderr, "usage: see source\n"), 2);
	seed_rng();
	if (!strcmp(av[1], "gen") && ac >= 3)
		return (run_gen(ac, av));
	if (!strcmp(av[1], "mix") && ac == 4)
		return (cmd_mix(atoi(av[2]), atoi(av[3])));
	if (!strcmp(av[1], "disorder"))
		return (cmd_disorder(ac - 2, av + 2));
	if (!strcmp(av[1], "check"))
		return (cmd_check(ac - 2, av + 2));
	if (!strcmp(av[1], "solve"))
		return (cmd_solve(ac - 2, av + 2));
	if (!strcmp(av[1], "randops") && ac == 3)
		return (cmd_randops(atoi(av[2])));
	return (fprintf(stderr, "ps_tool: bad command\n"), 2);
}
