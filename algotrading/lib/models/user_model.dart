class UserModel {
  final String accessToken;
  final String userId;
  final String userName;
  final String email;
  final String userType;
  final String broker;
  final List<String> exchanges;
  final List<String> products;

  UserModel({
    required this.accessToken,
    required this.userId,
    required this.userName,
    required this.email,
    required this.userType,
    required this.broker,
    required this.exchanges,
    required this.products,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      accessToken: json['access_token'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      email: json['email'] as String,
      userType: json['user_type'] as String,
      broker: json['broker'] as String,
      exchanges: List<String>.from(json['exchanges'] as List),
      products: List<String>.from(json['products'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'user_id': userId,
      'user_name': userName,
      'email': email,
      'user_type': userType,
      'broker': broker,
      'exchanges': exchanges,
      'products': products,
    };
  }
}
