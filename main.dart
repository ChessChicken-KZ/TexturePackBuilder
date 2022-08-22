import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart';

enum pattern_types {
  redirect,
  text,
  build_32,
  build_64,
  build_128,
  build_256
}

enum operations {
  CHECK,
  DEBUG,
  BUILD,
}

operations? defineOperation(String a) {
  switch(a) {
    case "CHECK": return operations.CHECK;
    case "DEBUG": return operations.DEBUG;
    case "BUILD": return operations.BUILD;
  }

  return null;
}

Image provideType(pattern_types a) {
  if(!a.name.startsWith("build_"))
    throw new Exception("Wrong enum for providing!");

  Image? image;
  switch(a) { // ignore: missing_enum_constant_in_switch
    case pattern_types.build_32: image = Image(32, 32); break;
    case pattern_types.build_64: image = Image(64, 64); break;
    case pattern_types.build_128: image = Image(128, 128); break;
    case pattern_types.build_256: image = Image(256, 256); break;
  }

  if(image != null) {
    fill(image, getColor(255, 255, 255));
    return image;
  }

  throw new Exception("Wrong enum for providing!"); //Impossible!
}

pattern_types? parseType(String s) {
  switch(s) {
    case "redirect": return pattern_types.redirect;
    case "text": return pattern_types.text;
    case "build_32": return pattern_types.build_32;
    case "build_64": return pattern_types.build_64;
    case "build_128": return pattern_types.build_128;
    case "build_256": return pattern_types.build_256;
  }
  return null;
}

void debug(String s) {
  DateTime current = DateTime.now();
  print("[${current.hour}:${current.minute}:${current.second}.${current.millisecond}] [Builder] ${s}");
}

abstract class PatternComponent {
  pattern_types pattern();

  void execute();
}

class PatternRedirect implements PatternComponent {
  String resource;
  String destination;

  PatternRedirect(String file, String get): destination = "build/" + file, resource = "dev/" + get;

  @override
  void execute() {
    File f = File(resource);
    if(!f.existsSync()) {
      debug("Couldn't find file [$resource]... skipping!");
      return;
    }
    File to = File(destination);
    to.createSync(recursive: true);
    f.copySync(to.path);
    debug("Redirect [$resource] -> [$destination].");
  }

  @override
  pattern_types pattern() {
    return pattern_types.redirect;
  }

  @override
  String toString() {
    return "redirect { 'resource'=$resource, 'destination'=$destination }";
  }
}

class PatternText implements PatternComponent {
  String destination;
  List<String> file;

  PatternText(String a): destination = 'build/' + a, file = List.empty(growable: true);

  PatternText.fromList(String a, List<String> b): destination = 'build/' + a, file = b;

  PatternText.fill(String a, String b): destination = 'build/' + a, file = b.split("\n");

  PatternText.mutate(String a, List b): destination = 'build/' + a, file = List.empty(growable: true) {
    for(Object c in b) {
      file.add(c.toString());
    }
  }

  @override
  void execute() {
    File q = File(destination);
    q.createSync(recursive: true);
    q.writeAsStringSync(file.join("\n"));
    debug("Generating and writing file... [$destination]");
  }

  @override
  pattern_types pattern() {
    return pattern_types.text;
  }

  @override
  String toString() {
    return "text { 'destination'=$destination, 'file'=${file.toString()} }";
  }

}

class PatternBuild implements PatternComponent {
  pattern_types type;
  String destination;
  Map<String, List<int>> values = Map();
  String? template;

  PatternBuild(pattern_types a, String b, Map c, String? d) : type = a, destination = "build/" + b {
    if(!type.name.startsWith("build_"))
      throw new Exception("Stupid! Check code and fix it!");
    template = d;
    c.forEach((key, value) {
      values["dev/" + key] = [(value as List)[0], (value)[1], (value)[2], (value)[3]];
    });
  }

  @override
  void execute() {
    Image image;
    if(template != null) {
      File temp = File("dev/" + template!);
      if(!temp.existsSync()) {
        debug("Error while getting file for texture! [template not found -> ${temp.path}]");
        return;
      }
      image = decodeImage(temp.readAsBytesSync())!;
    }else
      image = provideType(type);

    values.forEach((key, value) {
      File q = File(key);
      if(!q.existsSync()) {
        debug("Error while getting file for texture! [file not found -> $key]");
        return;
      }
      if(value[0] < 0 || value[0] > image.width || value[1] < 0 || value[1] > image.height) {
        debug("Error while applying image manipulations! [out of bounds -> image {${image.width}, ${image.height}}, coordinates {${value[0]}, ${value[1]}} ]");
        return;
      }

      Image texture = decodeImage(q.readAsBytesSync())!;

      debug("Applying texture... [$key -> $destination {${value[0]}, ${value[1]}}]");
      drawImage(image, texture,
          dstX: value[0], dstY: value[1],
          srcX: 0, srcY: 0,
          srcW: value[2], srcH: value[3],
          blend: false);
    });
    File(destination).writeAsBytesSync(encodePng(image));
    debug("Image manipulation complete! [$destination]");
  }

  @override
  pattern_types pattern() {
    return type;
  }

  @override
  String toString() {
    return "build { 'type'=$type, 'destination'=$destination, 'template'=$template, 'values'=${values.toString()} }";
  }

}

late operations default_operation;

void main() {
  String? a = Platform.environment['TEXTUREBUILDER'];
  default_operation = a == null ? operations.CHECK : defineOperation(a)!;

  debug("Texture Builder version 1.0...");
  debug("Mode: \"${default_operation.name}\"");
  File build_prop = File("build.json");
  if(!build_prop.existsSync()) {
    debug("Build description file not found! Please provide it as \"build.json\"");
    return;
  }

  final values = jsonDecode(build_prop.readAsStringSync());
  String t_name = values['name'];
  List? t_description = values['description'];
  String t_version = values['version'];
  debug('Found project! Name: \'$t_name\', version: \'$t_version\'');

  List patterns = values['pattern'];
  List<PatternComponent> components = List.empty(growable: true);

  if(t_description != null) {
    components.add(new PatternText.mutate("pack.txt", t_description));
  }

  for(Map map in patterns) {
    String? p_type = map['type'];
    if(p_type == null || p_type.length < 1) {
      debug("Error while parsing a pattern content! [type not found] (${map.toString()})");
      continue;
    }
    pattern_types? a_p_type = parseType(p_type);
    if(a_p_type == null) {
      debug("Error while parsing a pattern content! [type undefined] (${map.toString()})");
      continue;
    }
    switch(a_p_type) { // ignore: missing_enum_constant_in_switch
      case pattern_types.redirect:
        components.add(PatternRedirect(map['file'], map['get']));
        continue;
      case pattern_types.build_32:
        components.add(PatternBuild(pattern_types.build_32, map['file'], map['build'], map['base']));
        continue;
      case pattern_types.build_64:
        components.add(PatternBuild(pattern_types.build_64, map['file'], map['build'], map['base']));
        continue;
      case pattern_types.build_128:
        components.add(PatternBuild(pattern_types.build_128, map['file'], map['build'], map['base']));
        continue;
      case pattern_types.build_256:
        components.add(PatternBuild(pattern_types.build_256, map['file'], map['build'], map['base']));
        continue;
    }
  }

  switch(default_operation) {
    case operations.CHECK: {
      debug("Well... running builder in \"${default_operation.name}\" mode.");
      return;
    }
    case operations.BUILD: {
      debug("Building a texturepack...");
      File temp = File('build');
      if(temp.existsSync())
        temp.deleteSync(recursive: true);
      for(PatternComponent component in components) {
        component.execute();
      }
      debug("Project built! Exiting...");
      return;
    }
    case operations.DEBUG: {
      print("~~~~~");
      debug("Dumping all data...");
      for(PatternComponent component in components) {
        debug(component.toString());
      }
    }
  }

}

