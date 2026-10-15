/*
 * ps_tool - helper for push_swap_tester (not part of any 42 submission).
 *
 *   ps_tool gen N [MIN MAX]      N unique random ints in [MIN, MAX]
 *   ps_tool mix N PCT            sorted list with PCT% of positions shuffled
 *   ps_tool disorder ARGS...     disorder of ARGS as a percentage (%.2f)
 *   ps_tool check ARGS... < ops  reference checker: OK / KO / Error
 *   ps_tool solve ARGS...        prints a (naive) valid sorting sequence
 *   ps_tool randops K            prints K random valid instructions
 *
 * Seed with the SEED environment variable for reproducible runs.
 */
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct s_stack
{
	long	*v;
	int		n;
}	t_stack;

static const char	*g_ops[] = {"sa", "sb", "ss", "pa", "pb", "ra", "rb",
	"rr", "rra", "rrb", "rrr"};

static void	seed_rng(void)
{
	const char	*s = getenv("SEED");

	if (s && *s)
		srandom((unsigned)strtoul(s, NULL, 10));
	else
		srandom((unsigned)time(NULL) ^ ((unsigned)getpid() << 16));
}

static long	rnd(long lo, long hi)
{
	unsigned long long	r;

	r = ((unsigned long long)random() << 31) ^ (unsigned long long)random();
	return (lo + (long)(r % (unsigned long long)(hi - lo + 1)));
}

static int	parse_int(const char *s, long *out)
{
	char	*end;
	long	v;

	if (!*s)
		return (0);
	errno = 0;
	v = strtol(s, &end, 10);
	if (errno || *end || v < INT_MIN || v > INT_MAX
		|| !((*s >= '0' && *s <= '9') || ((*s == '-' || *s == '+')
				&& s[1] >= '0' && s[1] <= '9')))
		return (0);
	*out = v;
	return (1);
}

/* Parses argv (each arg may hold several space separated numbers). */
static int	parse_stack(int ac, char **av, t_stack *a)
{
	int		i;
	int		j;
	char	*dup;
	char	*tok;

	a->v = malloc(sizeof(long) * 100000);
	a->n = 0;
	for (i = 0; i < ac; i++)
	{
		dup = strdup(av[i]);
		tok = strtok(dup, " \t");
		if (!tok)
			return (free(dup), 0);
		while (tok)
		{
			if (!parse_int(tok, &a->v[a->n]))
				return (free(dup), 0);
			for (j = 0; j < a->n; j++)
				if (a->v[j] == a->v[a->n])
					return (free(dup), 0);
			a->n++;
			tok = strtok(NULL, " \t");
		}
		free(dup);
	}
	return (1);
}

static void	swap(t_stack *s)
{
	long	t;

	if (s->n < 2)
		return ;
	t = s->v[0];
	s->v[0] = s->v[1];
	s->v[1] = t;
}

static void	push(t_stack *dst, t_stack *src)
{
	if (!src->n)
		return ;
	memmove(dst->v + 1, dst->v, sizeof(long) * dst->n);
	dst->v[0] = src->v[0];
	dst->n++;
	src->n--;
	memmove(src->v, src->v + 1, sizeof(long) * src->n);
}

static void	rot(t_stack *s)
{
	long	t;

	if (s->n < 2)
		return ;
	t = s->v[0];
	memmove(s->v, s->v + 1, sizeof(long) * (s->n - 1));
	s->v[s->n - 1] = t;
}

static void	rrot(t_stack *s)
{
	long	t;

	if (s->n < 2)
		return ;
	t = s->v[s->n - 1];
	memmove(s->v + 1, s->v, sizeof(long) * (s->n - 1));
	s->v[0] = t;
}

static int	apply(const char *op, t_stack *a, t_stack *b)
{
	if (!strcmp(op, "sa")) swap(a);
	else if (!strcmp(op, "sb")) swap(b);
	else if (!strcmp(op, "ss")) { swap(a); swap(b); }
	else if (!strcmp(op, "pa")) push(a, b);
	else if (!strcmp(op, "pb")) push(b, a);
	else if (!strcmp(op, "ra")) rot(a);
	else if (!strcmp(op, "rb")) rot(b);
	else if (!strcmp(op, "rr")) { rot(a); rot(b); }
	else if (!strcmp(op, "rra")) rrot(a);
	else if (!strcmp(op, "rrb")) rrot(b);
	else if (!strcmp(op, "rrr")) { rrot(a); rrot(b); }
	else
		return (0);
	return (1);
}

static int	cmd_check(int ac, char **av)
{
	t_stack	a;
	t_stack	b;
	char	line[64];
	int		c;
	int		len;
	int		i;

	if (ac == 0)
		return (0);
	if (!parse_stack(ac, av, &a))
		return (fprintf(stderr, "Error\n"), 1);
	b.v = malloc(sizeof(long) * (a.n + 1));
	b.n = 0;
	len = 0;
	while ((c = getchar()) != EOF)
	{
		if (c == '\n')
		{
			line[len] = 0;
			if (!apply(line, &a, &b))
				return (fprintf(stderr, "Error\n"), 1);
			len = 0;
		}
		else if (len < 63)
			line[len++] = (char)c;
		else
			return (fprintf(stderr, "Error\n"), 1);
	}
	if (len)
	{
		line[len] = 0;
		if (!apply(line, &a, &b))
			return (fprintf(stderr, "Error\n"), 1);
	}
	for (i = 1; i < a.n; i++)
		if (a.v[i - 1] > a.v[i])
			return (puts("KO"), 0);
	puts(b.n ? "KO" : "OK");
	return (0);
}

static int	cmd_gen(int n, long lo, long hi)
{
	long	*v;
	long	range;
	int		i;
	int		j;
	int		k;
	long	t;

	range = hi - lo + 1;
	if (n < 0 || range < n)
		return (fprintf(stderr, "gen: range too small\n"), 1);
	if (range <= 2000000)
	{
		v = malloc(sizeof(long) * range);
		for (i = 0; i < range; i++)
			v[i] = lo + i;
		for (i = 0; i < n; i++)
		{
			k = i + (int)rnd(0, range - 1 - i);
			t = v[i];
			v[i] = v[k];
			v[k] = t;
		}
	}
	else
	{
		v = malloc(sizeof(long) * (n + 1));
		for (i = 0; i < n; i++)
		{
			v[i] = rnd(lo, hi);
			for (j = 0; j < i; j++)
				if (v[j] == v[i])
				{
					i--;
					break ;
				}
		}
	}
	for (i = 0; i < n; i++)
		printf(i ? " %ld" : "%ld", v[i]);
	printf("\n");
	return (0);
}

static int	cmd_mix(int n, int pct)
{
	int		*pos;
	long	*v;
	int		i;
	int		k;
	int		j;
	long	t;

	v = malloc(sizeof(long) * (n + 1));
	pos = malloc(sizeof(int) * (n + 1));
	for (i = 0; i < n; i++)
	{
		v[i] = i - n / 2;
		pos[i] = i;
	}
	k = n * pct / 100;
	for (i = 0; i < k; i++)
	{
		j = i + (int)rnd(0, n - 1 - i);
		t = pos[i];
		pos[i] = pos[j];
		pos[j] = (int)t;
	}
	for (i = k - 1; i > 0; i--)
	{
		j = (int)rnd(0, i);
		t = v[pos[i]];
		v[pos[i]] = v[pos[j]];
		v[pos[j]] = t;
	}
	for (i = 0; i < n; i++)
		printf(i ? " %ld" : "%ld", v[i]);
	printf("\n");
	return (0);
}

static int	cmd_disorder(int ac, char **av)
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
	for (i = 0; i < a.n; i++)
		for (j = i + 1; j < a.n; j++)
		{
			tot++;
			bad += a.v[i] > a.v[j];
		}
	printf("%.2f\n", tot ? 100.0 * (double)bad / (double)tot : 0.0);
	return (0);
}

/* Selection sort: rotate min to top, pb, repeat; then pa everything. */
static int	cmd_solve(int ac, char **av)
{
	t_stack	a;
	t_stack	b;
	int		i;
	int		mi;
	int		pushed;

	if (!parse_stack(ac, av, &a))
		return (fprintf(stderr, "Error\n"), 1);
	b.v = malloc(sizeof(long) * (a.n + 1));
	b.n = 0;
	pushed = 0;
	while (a.n > 0)
	{
		mi = 0;
		for (i = 1; i < a.n; i++)
			if (a.v[i] < a.v[mi])
				mi = i;
		while (mi != 0)
		{
			if (mi <= a.n / 2)
			{
				puts("ra");
				rot(&a);
				mi--;
			}
			else
			{
				puts("rra");
				rrot(&a);
				mi = (mi + 1) % a.n;
			}
		}
		puts("pb");
		push(&b, &a);
		pushed++;
	}
	while (pushed--)
		puts("pa");
	return (0);
}

static int	cmd_randops(int k)
{
	while (k-- > 0)
		puts(g_ops[rnd(0, 10)]);
	return (0);
}

int	main(int ac, char **av)
{
	if (ac < 2)
		return (fprintf(stderr, "usage: see source\n"), 2);
	seed_rng();
	if (!strcmp(av[1], "gen") && ac >= 3)
		return (cmd_gen(atoi(av[2]), ac > 3 ? atol(av[3]) : INT_MIN,
				ac > 4 ? atol(av[4]) : INT_MAX));
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
