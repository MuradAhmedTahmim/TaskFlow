from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

User = get_user_model()


class UserSummarySerializer(serializers.ModelSerializer):
    """Small public representation used inside projects, tasks and comments."""

    display_name = serializers.CharField(read_only=True)

    class Meta:
        model = User
        fields = ["id", "username", "email", "full_name", "display_name"]


class UserProfileSerializer(serializers.ModelSerializer):
    display_name = serializers.CharField(read_only=True)

    class Meta:
        model = User
        fields = [
            "id", "username", "email", "full_name", "display_name",
            "job_title", "bio", "date_joined", "last_login",
        ]
        read_only_fields = ["id", "date_joined", "last_login"]

    def validate_email(self, value):
        value = value.strip().lower()
        qs = User.objects.filter(email__iexact=value)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("This email is already in use.")
        return value

    def validate_username(self, value):
        value = value.strip()
        qs = User.objects.filter(username__iexact=value)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("This username is already taken.")
        return value


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, style={"input_type": "password"})
    password2 = serializers.CharField(write_only=True, style={"input_type": "password"}, label="Confirm password")

    class Meta:
        model = User
        fields = ["id", "username", "email", "full_name", "password", "password2"]

    def validate_email(self, value):
        value = value.strip().lower()
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate_username(self, value):
        value = value.strip()
        if User.objects.filter(username__iexact=value).exists():
            raise serializers.ValidationError("This username is already taken.")
        return value

    def validate(self, attrs):
        if attrs["password"] != attrs.pop("password2"):
            raise serializers.ValidationError({"password2": "Passwords do not match."})
        candidate = User(username=attrs.get("username"), email=attrs.get("email"), full_name=attrs.get("full_name", ""))
        validate_password(attrs["password"], user=candidate)
        return attrs

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True)

    def validate_old_password(self, value):
        if not self.context["request"].user.check_password(value):
            raise serializers.ValidationError("Current password is incorrect.")
        return value

    def validate_new_password(self, value):
        validate_password(value, user=self.context["request"].user)
        return value


class LoginSerializer(TokenObtainPairSerializer):
    """Accepts a username *or* an email address in the `username` field and
    returns the user profile alongside the tokens."""

    def validate(self, attrs):
        login = attrs.get(self.username_field, "").strip()
        if "@" in login:
            user = User.objects.filter(email__iexact=login).first()
            if user:
                attrs[self.username_field] = user.username
        data = super().validate(attrs)
        data["user"] = UserProfileSerializer(self.user).data
        return data
