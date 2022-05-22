def as_bool(x)
  if x.to_s == 'true'
    return true
  elsif x.to_s == 'false'
    return false
  else
    return false
  end
end

def list_htmls(path)
  files = Dir[path];
  return files
end

