library sample.named;

import 'src/util.dart';
import 'src/fallback.dart' if (dart.library.io) 'src/io_impl.dart';
import 'package:config_only/config_only.dart';
import 'package:support_pkg/support.dart';
export 'src/util.dart' show helper;
part 'src/piece.dart';
part 'src/by_name.dart';

/// A generic greeter.
class Greeter<T> {
  final int count = 1;
  static const String label = 'ok';

  Greeter();

  /// Named builder.
  Greeter.named( String name ) : this();

  factory Greeter.make() => Greeter.named( supportMessage() + configMessage() );

  int get total => count;
  set total( int value ) { helper( value ); }

  Future<int> run( int value ) async => helper<int>( value );
}

mixin Loud {
  void shout() { helper( 1 ); }
}

extension FancyText on String {
  int sized() => length;
}

extension type UserId( int rawValue ) {
  int raw() => rawValue;
}

enum Mode { fast, slow }

typedef Mapper = int Function( String value );

int get answer => helper( 41 );
set answer( int value ) { helper( value ); }
