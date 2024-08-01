prefix=/usr
bindir=$(prefix)/bin
libexecdir=$(prefix)/libexec/restic
sysconfdir=/etc
unitdir=$(sysconfdir)/systemd/system
localstatedir=/var
cachedir=$(localstatedir)/cache/restic
tmpfilesdir=$(sysconfdir)/tmpfiles.d

BUILDDIR=./build

RESTIC_USER=restic
RESTIC_GROUP=restic

RESTIC_BIN=$(shell command -v restic 2> /dev/null)

# Check if restic is installed
$(if $(RESTIC_BIN), $(info found $(shell $(RESTIC_BIN) version) at $(RESTIC_BIN)), $(error "restic command not found"))

TIMERS = \
	restic-backup-daily@.timer \
	restic-backup-weekly@.timer \
	restic-backup-monthly@.timer \
	restic-check-daily@.timer \
	restic-check-weekly@.timer \
	restic-check-monthly@.timer

SERVICES = \
	restic-backup@.service \
	restic-check@.service

UNITS = \
	$(SERVICES) \
	$(TIMERS)

BINSCRIPTS = restic-helper
LIBEXECSCRIPTS = restic-backup

SCRIPTS = \
	$(BINSCRIPTS) \
	$(LIBEXECSCRIPTS)

OUTFILES = \
	$(addprefix $(BUILDDIR)/, \
		$(UNITS) \
		$(SCRIPTS) \
		restic-tmpfiles.conf \
)

INSTALL = install

all: $(OUTFILES)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/restic-%@.timer: restic-service.timer $(BUILDDIR)
	@echo generating $@
	@schedule=$(shell echo $@ | cut -f1 -d@ | cut -f3 -d-); \
	service=$(shell echo $@ | cut -f1 -d@ | cut -f2 -d-); \
	sed \
		-e "s|@schedule@|$$schedule|g" \
		-e "s|@service@|$$service|g" \
		$< > $@ || rm -f $@

$(BUILDDIR)/restic-%: restic-%.in $(BUILDDIR)
	@echo generating $@
	@sed -e "s|@RESTIC_USER@|${RESTIC_USER}|g" \
			-e "s|@RESTIC_GROUP@|${RESTIC_GROUP}|g" \
			-e "s|@RESTIC_BIN@|$(RESTIC_BIN)|g" \
			-e "s|@RESTIC_CACHE_DIR@|${cachedir}|g" \
			-e "s|@RESTIC_BACKUP@|$(libexecdir)/restic-backup|g" \
			-e "s|@RESTIC_HELPER@|$(bindir)/restic-helper|g" \
			$< > $@ || rm -f $@

install: install-tmpfiles install-units install-libexec install-bin install-config

install-bindir:
	$(INSTALL) -d -m 755 $(DESTDIR)$(bindir)

install-bin: install-bindir $(addprefix $(BUILDDIR)/, $(BINSCRIPTS))
	for x in $(BINSCRIPTS); do \
		$(INSTALL) -m 755 -o $(RESTIC_USER) -g $(RESTIC_GROUP) $(BUILDDIR)/$$x $(DESTDIR)$(bindir); \
	done

install-libexecdir:
	$(INSTALL) -d -m 750 -o $(RESTIC_USER) -g $(RESTIC_GROUP) $(DESTDIR)$(libexecdir)

install-libexec: install-libexecdir $(addprefix $(BUILDDIR)/, $(LIBEXECSCRIPTS))
	for x in $(LIBEXECSCRIPTS); do \
		$(INSTALL) -m 750 -o $(RESTIC_USER) -g $(RESTIC_GROUP) $(BUILDDIR)/$$x $(DESTDIR)$(libexecdir); \
	done

install-tmpfiles: $(BUILDDIR)/restic-tmpfiles.conf
	$(INSTALL) -m 755 -d $(DESTDIR)$(tmpfilesdir)
	$(INSTALL) -m 644 $< $(DESTDIR)$(tmpfilesdir)/restic.conf
	systemctl restart systemd-tmpfiles-clean.service

install-units: install-services install-timers
	systemctl daemon-reload

install-services: $(addprefix $(BUILDDIR)/, $(SERVICES))
	$(INSTALL) -m 755 -d $(DESTDIR)$(unitdir)
	for unit in $(SERVICES); do \
		$(INSTALL) -m 644 $(BUILDDIR)/$$unit $(DESTDIR)$(unitdir); \
	done

install-timers: $(addprefix $(BUILDDIR)/, $(TIMERS))
	$(INSTALL) -m 755 -d $(DESTDIR)$(unitdir)
	for unit in $(TIMERS); do \
		$(INSTALL) -m 644 $(BUILDDIR)/$$unit $(DESTDIR)$(unitdir); \
	done

install-config: etc
	if [ ! -f $(DESTDIR)$(sysconfdir)/restic/restic.conf ]; then \
		$(INSTALL) -d -m 755 $(DESTDIR)$(sysconfdir)/restic; \
		$(INSTALL) -m 644 etc/restic.conf $(DESTDIR)$(sysconfdir)/restic/restic.conf; \
		$(INSTALL) -m 644 etc/ssh.conf $(DESTDIR)$(sysconfdir)/restic/ssh.conf; \
		$(INSTALL) -m 400 -o $(RESTIC_USER) -g $(RESTIC_GROUP) etc/password $(DESTDIR)$(sysconfdir)/restic/password; \
		$(INSTALL) -d -m 755 $(DESTDIR)$(sysconfdir)/restic/example; \
		$(INSTALL) -m 644 etc/example/restic.conf $(DESTDIR)$(sysconfdir)/restic/example/restic.conf; \
	fi

clean:
	rm -rf $(BUILDDIR)
