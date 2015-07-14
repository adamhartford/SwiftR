Pod::Spec.new do |s|
  s.name = 'SwiftR'
  s.version = '0.6.1'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.summary = 'Swift client for SignalR'
  s.homepage = 'https://github.com/adamhartford/SwiftR'
  s.social_media_url = 'http://twitter.com/adamhartford'
  s.authors = { 'Adam Hartford' => 'adam@adamhartford.com' }
  s.source = { :git => 'https://github.com/adamhartford/SwiftR.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'

  s.source_files = 'SwiftR/*.swift'
  s.resources = 'SwiftR/Web/*.js'

  s.requires_arc = true
end
