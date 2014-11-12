Gem::Specification.new do |s| 
  s.name              = "omnigollum"
  s.version           = '0.1.4'
  s.date              = Time.now.strftime('%Y-%m-%d')
  s.summary           = "Omnigollum makes it easy to use OmniAuth with Gollum"
  s.homepage          = "https://github.com/arr2036/omnigollum"
  s.email             = "a.cudbardb@gmail.com"
  s.authors           = [ "Arran Cudbard-Bell", "Tenshi Hinanawi" ]
  s.licenses          = [ "MIT" ]

  s.rdoc_options = ["--charset=UTF-8"]
  s.extra_rdoc_files = %w[Readme.md LICENSE]
  
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("public/**/*")
  s.files            += Dir.glob("templates/**/*")
  s.files            += Dir.glob("views/**/*")
  
  s.add_dependency('gollum')
  s.add_dependency('omniauth')
  s.add_dependency('mustache', '>= 0.99.5')
  
  s.description       = <<desc
Omnigollum adds support for OmniAuth in Gollum. It executes an OmniAuth::Builder proc/block to figure out which providers you've configured, then passes it on to omniauth to create the actual omniauth configuration.

See https://github.com/arr2036/omnigollum for usage instructions.
desc
end
