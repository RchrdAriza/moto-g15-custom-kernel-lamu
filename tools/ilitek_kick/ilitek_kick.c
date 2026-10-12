// SPDX-License-Identifier: GPL-2.0
/*
 * ilitek_kick: simula la interrupción del touch ILITEK para que el driver
 * tp_ilitek ejecute su propia recuperación (reset + recarga de firmware).
 *
 * Con pantallas de repuesto en lamu, el touch pierde su firmware al apagar el
 * panel y el driver solo lo recarga si llega una interrupción después del
 * resume. Cuando esa interrupción no llega, el touch queda muerto. Este módulo
 * permite dispararla desde userspace sin apagar la pantalla.
 *
 * No importa ningún símbolo del kernel (así no depende de los CRC de
 * MODVERSIONS): la dirección de generic_handle_irq_safe() se pasa como
 * parámetro, leída de /proc/kallsyms.
 *
 * Uso:
 *   insmod ilitek_kick.ko handler=0x<dirección de generic_handle_irq_safe>
 *   echo <irq de ilitek en /proc/interrupts> > /sys/module/ilitek_kick/parameters/kick
 */
#include <linux/module.h>
#include <linux/moduleparam.h>

typedef int (*handle_irq_fn)(unsigned int irq);

static unsigned long handler;
static unsigned long last_irq;

/* Parser propio en vez de kstrtoul() para no importar símbolos. */
static int parse_ulong(const char *s, unsigned long *out)
{
	unsigned long v = 0;
	unsigned int base = 10;
	int digits = 0;

	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
		base = 16;
		s += 2;
	}
	for (; *s && *s != '\n'; s++, digits++) {
		unsigned int d;

		if (*s >= '0' && *s <= '9')
			d = *s - '0';
		else if (base == 16 && *s >= 'a' && *s <= 'f')
			d = *s - 'a' + 10;
		else if (base == 16 && *s >= 'A' && *s <= 'F')
			d = *s - 'A' + 10;
		else
			return -EINVAL;
		v = v * base + d;
	}
	if (!digits)
		return -EINVAL;
	*out = v;
	return 0;
}

static int handler_set(const char *val, const struct kernel_param *kp)
{
	unsigned long addr;
	int ret = parse_ulong(val, &addr);

	if (ret)
		return ret;
	/* Debe ser una dirección del kernel (mitad alta en arm64). */
	if (addr < 0xffff000000000000UL)
		return -EINVAL;
	handler = addr;
	return 0;
}

static int kick_set(const char *val, const struct kernel_param *kp)
{
	unsigned long irq;
	int ret = parse_ulong(val, &irq);

	if (ret)
		return ret;
	if (!handler)
		return -ENODEV;
	last_irq = irq;
	return ((handle_irq_fn)handler)(irq);
}

static const struct kernel_param_ops handler_ops = { .set = handler_set };
static const struct kernel_param_ops kick_ops = { .set = kick_set };

module_param_cb(handler, &handler_ops, &handler, 0200);
module_param_cb(kick, &kick_ops, &last_irq, 0200);

static int __init ilitek_kick_init(void)
{
	return handler ? 0 : -EINVAL;
}

static void __exit ilitek_kick_exit(void)
{
}

module_init(ilitek_kick_init);
module_exit(ilitek_kick_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Simula la interrupción del touch ILITEK para disparar su recuperación");
