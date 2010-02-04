%define		plugin	check_id-pilet
%include	/usr/lib/rpm/macros.perl
Summary:	Nagios plugin to check id.ee ticket validity
Name:		nagios-plugin-%{plugin}
Version:	0.13
Release:	1
License:	GPL
Group:		Networking
Source0:	%{plugin}.pl
Source1:	%{plugin}.cfg
BuildRequires:	rpm-perlprov >= 4.1-13
Requires:	nagios-core
Requires:	nagios-plugins-libs
Requires:	perl-IO-Socket-SSL
Requires:	perl-Nagios-Plugin >= 0.23-2
BuildArch:	noarch
BuildRoot:	%{tmpdir}/%{name}-%{version}-root-%(id -u -n)

%define		_plugindir	%{_prefix}/lib/nagios/plugins
%define		_sysconfdir	/etc/nagios/plugins

%description
This plugin checks checks for id.ee ticket validity.

%prep
%setup -qTc
install %{SOURCE0} %{plugin}
cp -a %{SOURCE1} %{plugin}.cfg

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT{%{_sysconfdir},%{_plugindir}}
install %{plugin} $RPM_BUILD_ROOT%{_plugindir}/%{plugin}
cp -a %{plugin}.cfg $RPM_BUILD_ROOT%{_sysconfdir}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644,root,root,755)
%attr(640,root,nagios) %config(noreplace) %verify(not md5 mtime size) %{_sysconfdir}/%{plugin}.cfg
%attr(755,root,root) %{_plugindir}/%{plugin}
