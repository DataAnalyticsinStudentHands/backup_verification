echo "This is the message body and contains the message" | mailx -v -r "someone@example.com" -s "This is the subject" -S smtp="mail.example.com:587" -S smtp-use-starttls -S smtp-auth=login -S smtp-auth-user="someone@example.com" -S smtp-auth-password="abc123" -S ssl-verify=ignore yourfriend@gmail.com

