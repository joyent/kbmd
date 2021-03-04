#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright 2020 Joyent, Inc.
#

include		$(PWD)/../../../build.env

STRAP_AREA =	$(PWD)/../../../proto.strap
CC =		$(STRAP_AREA)/usr/bin/gcc
CP =		/bin/cp
AR =		/usr/bin/ar
LN =		/bin/ln
RM =		/bin/rm
LIBCRYPTO =	$(DESTDIR)/.build/libsunw_crypto.a
PROTOINC =	$(DESTDIR)/usr/include
INSTALL =	/usr/sbin/install
ELFWRAP =	/usr/bin/elfwrap

_PROGS =	kbmd kbmadm reset-piv unlock
_STATIC_LIBS =	common.a pivy.a

PROGS =		$(_PROGS:%=out/%)
STATIC_LIBS =	$(_STATIC_LIBS:%=out/%)

PIVY_TARGETS =	pivy-tool pivy-box

CPPFLAGS =	-I$(PROTOINC) -Icommon -I. -D_POSIX_PTHREAD_SEMANTICS
CFLAGS =	-g -msave-args -m64 -std=gnu99 -fstack-protector-all \
		-Wall -Wno-unknown-pragmas
LDFLAGS =	-L$(DESTDIR)/lib/amd64 -L$(DESTDIR)/usr/lib/amd64
LDLIBS =	out/common.a -lumem -lssp -lcustr -lnvpair -lsocket

ifeq ($(ILLUMOS_ENABLE_DEBUG), yes)
    CPPFLAGS += -DDEBUG
endif

ifeq ($(ILLUMOS_ENABLE_DEBUG), exclusive)
    CPPFLAGS += -DDEBUG
endif

_COMMON_SRCS =		\
	common.c	\
	ecustr.c	\
	envlist.c	\
	kspawn.c

# Include errf here since it is shared between kbmd and kbmadm
COMMON_SRCS = $(_COMMON_SRCS:%=common/%) pivy/errf.c
COMMON_OBJS = $(COMMON_SRCS:%.c=%.o)

_KBMADM_SRCS =		\
	kbmadm.c	\
	recover.c
KBMADM_SRCS = $(_KBMADM_SRCS:%=kbmadm/%)
KBMADM_OBJS = $(KBMADM_SRCS:%.c=%.o) pivy/libssh/base64.o
KBMADM_LIBS = -lbunyan -ltecla -lzfs
out/kbmadm:	LDLIBS += $(KBMADM_LIBS)

_ZCP_SRCS =		\
	add_prog.lua	\
	activate_prog.lua
ZCP_SRCS =	$(_ZCP_SRCS:%=lua/%)
ZCP_SRCS_NUL =	$(_ZCP_SRCS:%.lua=out/%)
ZCP_OBJS =	out/zcp.o

_KBMD_SRCS =		\
	box.c		\
	cmds.c		\
	door.c		\
	event.c		\
	kbmd.c		\
	piv.c		\
	piv-bunyan.c	\
	plugin.c	\
	recover.c	\
	zpool_create.c
KBMD_SRCS =	$(_KBMD_SRCS:%=kbmd/%)
KBMD_OBJS =	$(KBMD_SRCS:%.c=%.o) $(ZCP_OBJS)
KBMD_LIBS =		\
	out/pivy.a	\
	$(LIBCRYPTO)	\
	-lbunyan	\
	-lrefhash	\
	-lscf		\
	-lsmbios	\
	-luuid		\
	-lz		\
	-lzfs		\
	-lzfs_core	\
	-lpcsc

KBMD_DIR = /usr/lib/kbm
KBMD_PLUGIN_DIR = $(KBMD_DIR)/plugins
KBMD_PLUGINS = triton kbm-plugin-1

out/kbmd:	LDLIBS += $(KBMD_LIBS)
# For flockfile and funlockfile
out/kbmd:	CPPFLAGS += -D__EXTENSIONS__ -D_REENTRANT

_RESET_PIV_SRCS =	reset-piv.c
RESET_PIV_SRCS =	$(_RESET_PIV_SRCS:%=util/%)
RESET_PIV_OBJS =	$(RESET_PIV_SRCS:%.c=%.o) kbmd/piv-bunyan.o
RESET_PIV_LIBS =	\
	out/pivy.a	\
	$(LIBCRYPTO)	\
	-lbunyan	\
	-lpcsc		\
	-lz

out/reset-piv:	LDLIBS += $(RESET_PIV_LIBS)

#
# We explicitly statically link the pivy code.  We do not want any potentially
# shared code pages with other programs in any of the pivy code.  Such
# sharing could open up kbmd to timing attacks in any code that's handling
# key material, which could make it vulnerable to unintentional disclosure.

_LIBSSH_OBJS =			\
	atomicio.o		\
	authfd.o		\
	base64.o		\
	bcrypt-pbkdf.o		\
	blowfish.o		\
	cipher.o		\
	digest-openssl.o	\
	hmac.o			\
	rsa.o			\
	ssh-ecdsa.o		\
	ssh-ed25519.o		\
	ssh-rsa.o		\
	sshbuf.o		\
	sshkey.o
LIBSSH_OBJS = $(_LIBSSH_OBJS:%=pivy/libssh/%)

_SSS_OBJS =		\
	hazmat.o	\
	randombytes.o
SSS_OBJS = $(_SSS_OBJS:%=pivy/sss/%)

_CHAPOLY_OBJS =		\
	chacha.o	\
	poly1305.o
CHAPOLY_OBJS = $(_CHAPOLY_OBJS:%=pivy/chapoly/%)

_ED25519_OBJS =		\
	blocks.o	\
	ed25519.o	\
	fe25519.o	\
	ge25519.o	\
	hash.o		\
	sc25519.o
ED25519_OBJS = $(_ED25519_OBJS:%=pivy/ed25519/%)

# NOTE: errf.c is included within the kbmd/kbmadm common objs
# The pivy sources are only included within kbmd
_PIVY_OBJS =			\
	debug.o			\
	ebox.o			\
	piv.o			\
	tlv.o			\
	utils.o
PIVY_OBJS = $(_PIVY_OBJS:%=pivy/%)

PIVY_A_OBJS =		\
	$(PIVY_OBJS)	\
	$(SSS_OBJS)	\
	$(LIBSSH_OBJS)	\
	$(CHAPOLY_OBJS)	\
	$(ED25519_OBJS)

_DEST_PROGS =	/usr/sbin/pivy-tool \
		/usr/sbin/pivy-box \
		/usr/sbin/kbmadm \
		/usr/lib/kbm/kbmd \
		/usr/lib/kbm/reset-piv \
		/usr/lib/kbm/unlock \
		/lib/svc/manifest/system/kbmd.xml \
		/lib/svc/method/kbmd \
		/usr/share/man/man1m/kbmd.1m \
		/usr/share/man/man1m/kbmadm.1m
_DEST_DIRS =	$(KBMD_DIR) $(KBMD_PLUGIN_DIR)

DEST_PROGS = $(_DEST_PROGS:%=$(DESTDIR)%)
DEST_DIRS = $(_DEST_DIRS:%=$(DESTDIR)%)
DEST_PLUGINS = $(KBMD_PLUGINS:%=$(DESTDIR)$(KBMD_PLUGIN_DIR)/%)

#
# Build Targets
#

.PHONY: all world
world: all
all: pivy-stamp $(STATIC_LIBS) $(PROGS)

out:
	-mkdir out

$(PROGS) $(STATIC_LIBS): out

pivy-stamp:
	git submodule update --init
	$(MAKE) -C pivy \
	    CC=$(CC) \
	    PROTO_AREA="$(DESTDIR)" \
	    PCSC_CFLAGS="" \
	    PCSC_LIBS="-L$(DESTDIR)/usr/lib/amd64 -lpcsc" \
	    CRYPTO_FLAGS="-I$(DESTDIR)/usr/include" \
	    CRYPTO_LIBS="$(LIBCRYPTO)" \
	    LIBRESSL_INC="$(DESTDIR)/usr/include" \
	    LIBCRYPTO="$(LIBCRYPTO)" \
	    $(PIVY_TARGETS)
	touch pivy-stamp

out/common.a: $(COMMON_OBJS)
	$(AR) -cr $@ $(COMMON_OBJS)

$(PIVY_A_OBJS): pivy-stamp
out/pivy.a: pivy-stamp $(PIVY_A_OBJS)
	$(AR) -cr $@ $(PIVY_A_OBJS)

common/%.o: common/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<
	$(CTFCONVERT) $@

kbmadm/%.o: kbmadm/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<
	$(CTFCONVERT) $@

kbmd/%.o: kbmd/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<
	$(CTFCONVERT) $@


out/kbmadm: $(KBMADM_OBJS) out/common.a
	$(CC) -o $@ $(CFLAGS) $(KBMADM_OBJS) $(LDFLAGS) $(LDLIBS)
	$(CTFCONVERT) $@

#
# The openssl bits don't currently have CTF info, so -m is needed
out/kbmd: $(KBMD_OBJS) $(STATIC_LIBS)
	$(CC) -o $@ $(CFLAGS) $(KBMD_OBJS) $(LDFLAGS) $(LDLIBS)
	$(CTFCONVERT) -m $@

out/%: lua/%.lua
	cp $^ $@.tmp
	printf '\0' >> $@.tmp
	mv $@.tmp $@

$(ZCP_OBJS): $(ZCP_SRCS_NUL)
	$(ELFWRAP) -64 -o $@ $(ZCP_SRCS_NUL)

out/reset-piv: $(RESET_PIV_OBJS) out/pivy.a out/kbmd
	$(CC) -o $@ $(CFLAGS) $(RESET_PIV_OBJS) $(LDFLAGS) $(LDLIBS)
	$(CTFCONVERT) -m $@
#
# Install Targets
#
.PHONY: install manifest

$(DESTDIR)/usr/sbin/%: pivy/%
	$(RM) -f $@; $(INSTALL) -m 0555 -f $(DESTDIR)/usr/sbin $<

$(DESTDIR)/usr/sbin/%: out/%
	$(RM) -f $@; $(INSTALL) -m 0555 -f $(DESTDIR)/usr/sbin $<

$(DESTDIR)/usr/share/man/man1m/%: man/%
	$(RM) -f $@; $(INSTALL) -m 0444 -f $(DESTDIR)/usr/share/man/man1m $<

$(DESTDIR)/lib/svc/method/%: smf/%
	$(RM) -f $@; $(INSTALL) -m 0555 -f $(DESTDIR)/lib/svc/method $<

$(DESTDIR)/lib/svc/manifest/system/%: smf/%
	$(RM) -f $@; $(INSTALL) -m 0644 -f $(DESTDIR)/lib/svc/manifest/system $<

$(DESTDIR)$(KBMD_DIR):
	-mkdir -m 0755 $@

$(DESTDIR)$(KBMD_PLUGIN_DIR): $(DESTDIR)/$(KBMD_DIR)
	-mkdir -m 0755 $@

$(DESTDIR)$(KBMD_DIR)/%: out/% $(DESTDIR)$(KBMD_DIR)
	$(RM) -f $@; $(INSTALL) -m 0555 -f $(DESTDIR)$(KBMD_DIR) $<

$(DESTDIR)$(KBMD_PLUGIN_DIR)/%: plugins/%
	$(RM) -f $@; $(INSTALL) -m 0555 -f $(DESTDIR)$(KBMD_PLUGIN_DIR) $<

$(DESTDIR)$(KBMD_PLUGIN_DIR)/kbm-plugin-1: $(DESTDIR)$(KBMD_PLUGIN_DIR)/triton
	$(RM) -f $@; $(LN) -s triton $@


install: all $(DEST_PROGS) $(DEST_DIRS) $(DEST_PLUGINS)

out/unlock: util/unlock
	$(CP) util/unlock $@

manifest:
	cp manifest $(DESTDIR)/$(DESTNAME)

mancheck_conf:

.PHONY: update
update:
	git pull --rebase

.PHONY: clean
clean:
	rm -f $(COMMON_OBJS) $(KBMADM_OBJS) $(KBMD_OBJS) $(RESET_PIV_OBJS) \
	    pivy-stamp out/*
	-rmdir out
	(cd pivy; $(MAKE) clean)
