/*
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source.  A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 */

/*
 * Copyright 2020 Joyent, Inc.
 */

#include <bunyan.h>
#include <err.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include "pivy/errf.h"
#include "pivy/piv.h"
#include "common.h"

SCARDCONTEXT ctx;

static void
usage(void)
{
	(void) fprintf(stderr,
	    "Usage: %s [guid]\n"
	    "  If multiple initialized PIV tokens are present on the system, \n"
	    "  the guid must be supplied\n",
	    getprogname());

	exit(EXIT_FAILURE);
}

static errf_t *
parse_guid(const char *str, uint8_t guid[GUID_LEN])
{
	const char *p = str;
	size_t n = 0;
	size_t shift = 4;

	while (*p != '\0') {
		const char c = *p++;

		if (n == GUID_LEN) {
			return (errf("LengthError", NULL,
			    "'%s' is not a valid GUID", str));
		}

		switch (c) {
		case '0': case '1': case '2': case '3': case '4':
		case '5': case '6': case '7': case '8': case '9':
			guid[n] |= (c - '0') << shift;
			break;
		case 'A': case 'B': case 'C': case 'D': case 'E': case 'F':
			guid[n] |= (c - 'A' + 10) << shift;
			break;
		case 'a': case 'b': case 'c': case 'd': case 'e': case 'f':
			guid[n] |= (c - 'a' + 10) << shift;
			break;
		case ' ': case ':': case '\t':
			continue;
		default:
			return (errf("InvalidCharacter", NULL,
			    "%c is not a valid hex digit", c));
		}

		if (shift == 4) {
			shift = 0;
		} else {
			shift = 4;
			n++;
		}
	}

	return (ERRF_OK);
}

static errf_t *
get_piv(const char *guidstr, struct piv_token **ptp)
{
	errf_t *ret = ERRF_OK;
	uint8_t guid[GUID_LEN] = { 0 };

	*ptp = NULL;

	if (guidstr != NULL) {
		ret = parse_guid(guidstr, guid);
		if (ret != ERRF_OK) {
			errfx(EXIT_FAILURE, ret, "failed to parse guid '%s'",
			    guidstr);
		}

		ret = piv_find(ctx, guid, GUID_LEN, ptp);
		if (ret != ERRF_OK) {
			return (errf("NotFoundError", ret,
			    "cannot find PIV token '%s'", guidstr));
		}
	}

	struct piv_token *tokens = NULL;
	struct piv_token *t = NULL;

	ret = piv_enumerate(ctx, &tokens);
	if (ret != ERRF_OK) {
		errfx(EXIT_FAILURE, ret, "failed to enumrate PIV tokens");
	}

	for (t = tokens; t != NULL; t = piv_token_next(t)) {
		const uint8_t *tguid = piv_token_guid(t);

		if (tguid == NULL)
			continue;

		if (guidstr != NULL && memcmp(tguid, guid, GUID_LEN) != 0)
			continue;

		if (*ptp != NULL) {
			return (errf("CardError", NULL,
			    "multiple PIV tokens present; must provide guid to "
			    "reset"));
		}

		*ptp = t;
	}

	/* We end up leaking the rest of tokens, but that's ok */

	if (*ptp == NULL) {
		return (errf("NotFoundError", NULL,
		    "no PIV tokens were found"));
	}

	return (ERRF_OK);
}

static const char *
piv_token_shortid(struct piv_token *pk)
{
	static char buf[9];

	if (piv_token_has_chuid(pk)) {
		/* Let strlcpy() truncate the GUID for us */
		(void) strlcpy(buf, piv_token_guid_hex(pk), sizeof (buf));
	} else {
		(void) snprintf(buf, sizeof (buf), "00000000");
	}

	return (buf);
}

static errf_t *
do_block(struct piv_token *pt, enum piv_pin type)
{
	char zero[] = "000000";
	char one[] = "111111";
	errf_t *ret = ERRF_OK;

	for (size_t i = 0; i < 4; i++) {
		ret = piv_change_pin(pt, type, zero, one);

		/*
		 * If for some reason the pin is '000000' we change the pin
		 * to something else and retry
		 */
		if (ret == ERRF_OK) {
			zero[0] = '1';
			continue;
		}

		if (errf_caused_by(ret, "MinRetriesError") ||
		    errf_caused_by(ret, "LockError")) {
			errf_free(ret);
			return (ERRF_OK);
		}

		if (errf_caused_by(ret, "PermissionError")) {
			errf_free(ret);
			continue;
		}

		/*
		 * Currently, pivy's piv_change_pin() doesn't indicate
		 * if the PIN has been blocked. Instead we have to rely
		 * on an APDU Error as a proxy. However, a PermissionError
		 * will also have an APDUError in it's error chain, so this
		 * check must happen _after_ the PermissionError check.
		 */
		if (errf_caused_by(ret, "APDUError")) {
			errf_free(ret);
			return (ERRF_OK);
		}

		return (errf("LockError", ret,
			    "error while attempting to lock PIV"));
	}

	return (errf("LockError", ret, "failed to lock PIV"));
}

static errf_t *
block_piv(struct piv_token *pt)
{
	errf_t *ret = ERRF_OK;

	(void) fprintf(stderr, "Blocking PIN...\n");
	ret = do_block(pt, piv_token_default_auth(pt));
	if (ret != ERRF_OK)
		return (ret);

	(void) fprintf(stderr, "Blocking PUK...\n");
	return (do_block(pt, PIV_PUK));
}

int
main(int argc, char * const * argv)
{
	errf_t *ret = ERRF_OK;
	struct piv_token *pt = NULL;
	char *resp = NULL;
	char *dbg = getenv("RESET_PIV_DEBUG");
	int rc;

	alloc_init();

	rc = bunyan_init(getprogname(), &tlog);
	if (rc != 0) {
		errx(EXIT_FAILURE, "failed to initialize bunyan logger: %s",
		    strerror(rc));
	}

	rc = bunyan_stream_add(tlog, "stderr",
	    (dbg == NULL) ? BUNYAN_L_INFO : BUNYAN_L_TRACE, bunyan_stream_fd,
	    (void *)STDERR_FILENO);
	if (rc != 0) {
		errx(EXIT_FAILURE, "failed to add stderr stream logger: %s",
		    strerror(rc));
	}

	if (dbg != NULL)
		piv_full_apdu_debug = B_TRUE;

	rc = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &ctx);
	if (rc != 0) {
		errx(EXIT_FAILURE, "could not initialize libpcsc: %s",
		    pcsc_stringify_error(rc));
	}

	ret = get_piv(argv[1], &pt);
	if (ret != ERRF_OK) {
		warnfx(ret, "failed to find PIV token to reset");
		usage();
	}

	if (!piv_token_is_ykpiv(pt)) {
		err(EXIT_FAILURE, "only Yubikeys are currently supported; "
		    "PIV token is not a Yubikey");
	}

	(void) fprintf(stderr, "Resetting Yubikey %s (%s)\n",
	    piv_token_shortid(pt), piv_token_rdrname(pt));

	if (ykpiv_token_has_serial(pt))
		(void) fprintf(stderr, "Serial #%u\n", ykpiv_token_serial(pt));

	(void) fprintf(stderr, "WARNING: this will completely reset the PIV applet "
	    "on this Yubikey, erasing all keys and certificates!\n");

	do {
		resp = getpass("Type 'YES' to continue: ");
	} while (resp == NULL && errno == EINTR);

	if (resp == NULL || strcmp(resp, "YES") != 0)
		return (EXIT_FAILURE);

	ret = piv_txn_begin(pt);
	if (ret != ERRF_OK)
		errfx(EXIT_FAILURE, ret, "failed to start PIV transation");

	ret = piv_select(pt);
	if (ret != ERRF_OK) {
		piv_txn_end(pt);
		errfx(EXIT_FAILURE, ret, "error while selecting PIV applet");
	}

	ret = block_piv(pt);
	if (ret != ERRF_OK)
		errfx(EXIT_FAILURE, ret, "failed to lock PIV token");

	ret = ykpiv_reset(pt);
	if (ret != ERRF_OK) {
		piv_txn_end(pt);
		errfx(EXIT_FAILURE, ret, "failed to factory reset YubiKey");
	}

	piv_txn_end(pt);
	return (0);
}
