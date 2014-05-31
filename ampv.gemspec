unless $:.include?(lib = File.expand_path("../lib", __FILE__))
  $:.unshift(lib)
end

require "date"
require "ampv/version"

Gem::Specification.new { |s|
  s.name        = Ampv::PACKAGE
  s.version     = Ampv::VERSION
  s.date        = Date.today.to_s
  s.summary     = "ampv"
  s.description = "A minimal GTK2 mpv frontend."
  s.authors     = [ "ahoka" ]
  s.homepage    = "https://github.com/ahodesuka/ampv"
  s.license     = "MIT"
  s.files       = Dir[ "LICENSE", "input.conf", "lib/**/*" ]
  s.executables = [ Ampv::PACKAGE ]

  s.default_executable    = Ampv::PACKAGE
  s.required_ruby_version = ">=1.9.3"
  s.add_runtime_dependency("gtk2")
  s.add_runtime_dependency("json")
  s.add_runtime_dependency("mpv")
  s.requirements << "mpv git"
}
