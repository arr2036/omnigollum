Gem::Specification.new do |s| 
  s.name              = "omnigollum"
  s.version           = '0.1.0'
  s.date              = Time.now.strftime('%Y-%m-%d')
  s.summary           =
        "Omnigollum makes it easy to use OmniAuth with Gollum"
  s.homepage          = "https://github.com/arr2036/omnigollum"
  s.email             = "cockmomgler@gmail.com"
  s.authors           = [ "Arran Cudbard-Bell", "Tenshi Hinanawi" ]
  
  s.rdoc_options = ["--charset=UTF-8"]
  s.extra_rdoc_files = %w[Readme.md LICENSE]
  
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("public/**/*")
  s.files            += Dir.glob("templates/**/*")
  s.files            += Dir.glob("views/**/*")
  
  s.add_dependency('gollum')
  s.add_dependency('omniauth')
  s.add_dependency('mustache')
  
  s.description       = <<desc
Omnigollum adds support for OmniAuth in Gollum. It executes an OmniAuth::Builder proc/block to figure out which providers you've configured, then passes it on to omniauth to create the actual omniauth configuration.

See https://github.com/arr2036/omnigollum for usage instructions.

Some of Omnigollum's dependencies had to be patched before use. These patches have already been made into dependent gems for your convenience.
desc
end
