/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   parse.c                                            :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: marvin <marvin@42.fr>                      +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/10/26 00:00:00 by marvin            #+#    #+#             */
/*   Updated: 2026/10/26 00:00:00 by marvin           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "ps_tool.h"

static int	parse_int(const char *s, long *out)
{
	const char	*d;
	char		*end;
	long		v;

	d = s;
	if (*d == '-' || *d == '+')
		d++;
	if (!(*d >= '0' && *d <= '9'))
		return (0);
	errno = 0;
	v = strtol(s, &end, 10);
	if (errno || *end || v < INT_MIN || v > INT_MAX)
		return (0);
	*out = v;
	return (1);
}

static int	add_number(t_stack *a, const char *tok)
{
	int	j;

	if (!parse_int(tok, &a->v[a->n]))
		return (0);
	j = 0;
	while (j < a->n)
	{
		if (a->v[j] == a->v[a->n])
			return (0);
		j++;
	}
	a->n++;
	return (1);
}

static int	parse_arg(t_stack *a, const char *arg)
{
	char	*dup;
	char	*tok;

	dup = strdup(arg);
	tok = strtok(dup, " \t");
	if (!tok)
		return (free(dup), 0);
	while (tok)
	{
		if (!add_number(a, tok))
			return (free(dup), 0);
		tok = strtok(NULL, " \t");
	}
	free(dup);
	return (1);
}

/* Parses argv (each arg may hold several space separated numbers). */
int	parse_stack(int ac, char **av, t_stack *a)
{
	int	i;

	a->v = malloc(sizeof(long) * 100000);
	a->n = 0;
	i = 0;
	while (i < ac)
	{
		if (!parse_arg(a, av[i]))
			return (0);
		i++;
	}
	return (1);
}
