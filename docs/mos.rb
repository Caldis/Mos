cask 'Mos' do
  version '1.4.4'
  sha256 'b7a33f6c619929dbddc7a7c8ae8b3a47934e8004'

  url 'https://github.com/Caldis/Mos/releases/download/1.4.4/Mos.Version.#{version}.dmg'
  name 'Mos'
  homepage 'http://mos.u2sk.com/'

  depends_on macos: '>= :el_capitan'

  app 'Mos.app'

  zap delete: '~/Library/Preferences/com.u2sk.Mos.plist'
end